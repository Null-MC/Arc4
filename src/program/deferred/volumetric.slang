import aperture;
import settings;
import lib.common;
import lib.noise.ign;
import lib.froxel;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.multiscatter;

static const int VL_NearSampleCount = 8;
static const int VL_FarSampleCount = 8;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texMain_write;

Texture2D<half3> texMain_read;

Texture3D<half4> texFroxel_write;
SamplerState froxelSampler;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.screenSize)) return;

    float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;
    float depth = ap.depth[globalPos];

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float viewDist = length(localPos);
    float3 localViewDir = localPos / viewDist;

    float3 skyPos = planet.getSkyPosition(0.0);

    float traceDistance_KM = planet.rayIntersectsAtmosphere(skyPos, localViewDir);

    if (planetSurfaceEnabled) {
        float groundDist = planet.rayIntersectsGround(skyPos, localViewDir);
        if (groundDist > 0.0) traceDistance_KM = min(traceDistance_KM, groundDist);
    }

    if (depth > 0.0) traceDistance_KM = min(traceDistance_KM, viewDist * 0.001);

    float traceDistanceNear_KM = min(traceDistance_KM, ap.camera.far * 0.001);

    float stepSizeNear_KM = traceDistanceNear_KM / VL_NearSampleCount;

    float traceDistanceNear = traceDistanceNear_KM * 1000.0;

    float traceDistanceFar_KM = traceDistance_KM - traceDistanceNear_KM;
    float traceDistanceFar = traceDistanceFar_KM * 1000.0;

    float3 viewDir = normalize(viewPos);
    float3 viewPosEndNear = viewDir * traceDistanceNear;

    float dither = IGN::getAnimated(globalPos);

    float3 scattering = 0.0;
    float3 transmittance = 1.0;

    for (int i = 0; i < VL_NearSampleCount; i++) {
        float stepF = (i + dither) / VL_FarSampleCount;

        // do not pre-interpolate like shadows, sky is not linear space
        float3 localPos_trace = localViewDir * (traceDistanceNear * stepF);
        float3 skyPos_trace = planet.getSkyPosition(localPos_trace);

        AtmosphereSample skySample;
        float altitude_KM = planet.getSkyAltitude(skyPos_trace);
        sky.Sample(altitude_KM, skySample);

        float3 sampleTransmittance = exp(-stepSizeNear_KM * skySample.extinction);

        float3 trace_viewPos = viewPosEndNear * stepF;
        float3 ndcPos = mul_project(ap.camera.projection, trace_viewPos);
        float3 trace_bufferPos = Froxel_GetBufferPosition(ndcPos);
        float3 froxel_uv = trace_bufferPos / Froxel_Resolution;

        float3 inScattering = texFroxel_write.Sample(froxelSampler, froxel_uv).rgb;

        // Integrated scattering within path segment.
        float3 scatteringIntegral = inScattering * ((1.0 - sampleTransmittance) / max(skySample.extinction, 1e-5));

        scattering += scatteringIntegral * transmittance;
        
        transmittance *= sampleTransmittance;
    }

    if (traceDistanceFar > 0.0) {
        float3 sunDir = normalize(ap.celestial.sunPosition);
        float cosTheta_sun = dot(localViewDir, sunDir);
        float miePhaseValue_sun = getMiePhase(cosTheta_sun);
        float rayleighPhaseValue_sun = getRayleighPhase(cosTheta_sun);

        float3 moonDir = normalize(ap.celestial.moonPosition);
        float cosTheta_moon = dot(localViewDir, moonDir);
        float miePhaseValue_moon = getMiePhase(cosTheta_moon);
        float rayleighPhaseValue_moon = getRayleighPhase(cosTheta_moon);

        float stepSizeFar_KM = traceDistanceFar_KM / VL_FarSampleCount;

        for (int i = 0; i < VL_FarSampleCount; i++) {
            float stepF = (i + dither) / VL_FarSampleCount;

            // do not pre-interpolate like shadows, sky is not linear space
            float3 localPos_trace = localViewDir * (traceDistanceFar * stepF + traceDistanceNear);
            float3 skyPos_trace = planet.getSkyPosition(localPos_trace);

            AtmosphereSample skySample;
            float altitude_KM = planet.getSkyAltitude(skyPos_trace);
            sky.Sample(altitude_KM, skySample);

            float3 sampleTransmittance = exp(-stepSizeFar_KM * skySample.extinction);

            float3 sunTransmittanceLux = planet.sampleTransmit(skyPos_trace, sunDir) * SunColor;
            float3 moonTransmittanceLux = planet.sampleTransmit(skyPos_trace, -sunDir) * MoonColor;

            float3 psiMS = planet.sampleMultiScatter(skyPos_trace, sunDir) + Sky_MinLight;
            //vec3 psiMS_moon = getValFromMultiScattLUT(texSkyMultiScatter, newPos, sunDir);

            float3 rayleighInScattering_sun = rayleighPhaseValue_sun * sunTransmittanceLux;
            float3 mieInScattering_sun = miePhaseValue_sun * sunTransmittanceLux;

            float3 rayleighInScattering_moon = rayleighPhaseValue_moon * moonTransmittanceLux;
            float3 mieInScattering_moon = miePhaseValue_moon * moonTransmittanceLux;

            float3 inScattering = skySample.rayleighScattering * (rayleighInScattering_sun + rayleighInScattering_moon + psiMS)
                            + skySample.mieScattering * (mieInScattering_sun + mieInScattering_moon + psiMS);

            // Integrated scattering within path segment.
            float3 scatteringIntegral = inScattering * ((1.0 - sampleTransmittance) / max(skySample.extinction, 1e-5));

            scattering += scatteringIntegral * transmittance;
            
            transmittance *= sampleTransmittance;
        }
    }

    float3 color = texMain_read[globalPos];

    color = color * transmittance + getColorSpace().fromLinear(scattering);

    color = clamp(color, 0.0, half.maxValue);

    texMain_write[globalPos] = color;
}
