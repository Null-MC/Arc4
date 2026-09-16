import aperture;
import settings;
import lib.common;
import lib.noise.ign;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.multiscatter;
import lib.sky.view;


extern static const int BufferWidth;
extern static const int BufferHeight;

static const int numScatteringSteps = 64;

[[vk::image_format("rgba16f")]]
RWTexture2D<half3> texSkyView;


half3 raymarchScattering(uint2 globalPos, float3 pos, float3 rayDir, float3 sunDir, float tMax) {
    float cosTheta = dot(rayDir, sunDir);
    
	float miePhaseValue_sun = getMiePhase(cosTheta);
	float rayleighPhaseValue_sun = getRayleighPhase(cosTheta);

    float miePhaseValue_moon = getMiePhase(-cosTheta);
    float rayleighPhaseValue_moon = getRayleighPhase(-cosTheta);

    float dither = IGN::getAnimated(globalPos);
    float stepSize = tMax / numScatteringSteps;

    float3 scattering = 0.0;
    float3 transmittance = 1.0;

    for (int i = 0; i < numScatteringSteps; i++) {
        float t = (i + dither) * stepSize;
        float3 newPos = pos + t*rayDir;
        
        AtmosphereSample skySample;
        float altitude_KM = planet.getSkyAltitude(newPos);
        // altitude_KM = max(altitude_KM, 1e-6);
        sky.Sample(altitude_KM, skySample);

        float3 sampleTransmittance = exp(-stepSize * skySample.extinction);

        float3 sunTransmittanceLux = planet.sampleTransmit(newPos, sunDir) * SunColor;
        float3 moonTransmittanceLux = planet.sampleTransmit(newPos, -sunDir) * MoonColor;

        float3 psiMS = planet.sampleMultiScatter(newPos, sunDir) + Sky_MinLight;
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

    return half3(scattering);
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= uint2(BufferWidth, BufferHeight))) return;
    float2 texcoord = (globalPos.xy + 0.5) / float2(BufferWidth, BufferHeight);

    float3 skyPos = planet.getSkyPosition(0.0);

    float3 rayDir, sunDir;
    HillaireSky::fromViewCoord(texcoord, planet, skyPos, rayDir, sunDir);
    
    float tMax = planet.rayIntersectsAtmosphere(skyPos, rayDir);

    if (planetSurfaceEnabled) {
        float groundDist = planet.rayIntersectsGround(skyPos, rayDir);
        if (groundDist > 0.0) tMax = groundDist;
    }

    half3 color_new = raymarchScattering(globalPos, skyPos, rayDir, sunDir, tMax);

    half3 color = texSkyView[globalPos];
    color = ap.timing.frameCounter < 1 ? color_new : lerp(color, color_new, 0.0625h);
    texSkyView[globalPos] = color;
}
