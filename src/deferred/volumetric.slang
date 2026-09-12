import aperture;
import lib.common;
import lib.ign;
import lib.shadows;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.multiscatter;

static const int VL_SampleCount = 16;

[[vk::image_format("rgba16f")]]
RWTexture2D<half3> mainTexture_write;

Texture2D<half3> mainTexture_read;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.screenSize)) return;

    float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;
    float depth = ap.opaqueDepth[globalPos];

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float viewDist = length(localPos);
    float3 localViewDir = localPos / viewDist;

    var planet = HillaireSky::currentPlanet();
    var sky = HillaireSky::currentSky();

    float3 skyPos = planet.getSkyPosition(0.0);
    float traceDistance_KM = planet.rayIntersectsAtmosphere(skyPos, localViewDir);
    if (depth > 0.0) traceDistance_KM = min(traceDistance_KM, viewDist * 0.001);
    float stepSize_KM = traceDistance_KM / VL_SampleCount;

    float traceDistance = traceDistance_KM * 1000.0;

    float3 shadowViewPos_start = mul3(ap.celestial.view, 0.0);
    float3 shadowViewPos_end = mul3(ap.celestial.view, localViewDir * traceDistance);

    float3 sunDir = normalize(ap.celestial.sunPosition);
    float cosTheta_sun = dot(localViewDir, sunDir);
	float miePhaseValue_sun = getMiePhase(cosTheta_sun);
	float rayleighPhaseValue_sun = getRayleighPhase(cosTheta_sun);

    float3 moonDir = normalize(ap.celestial.moonPosition);
    float cosTheta_moon = dot(localViewDir, moonDir);
    float miePhaseValue_moon = getMiePhase(cosTheta_moon);
    float rayleighPhaseValue_moon = getRayleighPhase(cosTheta_moon);

    float dither = InterleavedGradientNoiseTime(globalPos);

    float3 scattering = 0.0;
    float3 transmittance = 1.0;

    for (int i = 0; i < VL_SampleCount; i++) {
        float stepF = (i + dither) / VL_SampleCount;

        float3 shadowViewPos_trace = lerp(shadowViewPos_start, shadowViewPos_end, stepF);

        float shadowF = 1.0;
        if (let result = getShadowCascade(shadowViewPos_trace)) {
            shadowF = ap.opaqueShadow.compare(result.position.xy, result.cascade, result.position.z);
        }

        // do not pre-interpolate like shadows, sky is not linear space
        float3 localPos_trace = localViewDir * (traceDistance * stepF);
        float3 skyPos_trace = planet.getSkyPosition(localPos_trace);

        AtmosphereSample skySample;
        float altitude_KM = planet.getSkyAltitude(skyPos_trace);
        sky.Sample(altitude_KM, skySample);

        float3 sampleTransmittance = exp(-stepSize_KM * skySample.extinction);

        float3 sunTransmittanceLux = HillaireSky::sampleTransmit(planet, skyPos_trace, sunDir) * SunColor * shadowF;
        float3 moonTransmittanceLux = HillaireSky::sampleTransmit(planet, skyPos_trace, -sunDir) * MoonColor * shadowF;

        float3 psiMS = HillaireSky::sampleMultiScatter(planet, skyPos_trace, sunDir) + Sky_MinLight;
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

    half3 color = mainTexture_read[globalPos];

    color = half3(color * transmittance + scattering);

    mainTexture_write[globalPos] = color;
}
