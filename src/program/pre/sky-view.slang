import aperture;
import settings;
import lib.common;
import lib.noise.ign;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.multiscatter;
import lib.sky.view;
import lib.sky.clouds;


extern static const int BufferWidth;
extern static const int BufferHeight;

static const int numScatteringSteps = 64;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texSkyView;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texSkyViewClouds;


float3 raymarchScattering(uint2 globalPos, float3 pos, float3 rayDir, float3 sunDir, float tMax) {
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

    return scattering;
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= uint2(BufferWidth, BufferHeight))) return;
    float2 texcoord = (globalPos.xy + 0.5) / float2(BufferWidth, BufferHeight);

    float3 cameraLocalPos = 0.0;
    cameraLocalPos.y = max(userSettings.SeaLevel - ap.camera.position.y, 0.002);
    float3 cameraSkyPos = planet.getSkyPosition(cameraLocalPos);

    // float3 rayDir, sunDir;
    // HillaireSky::fromViewCoord(texcoord, planet, skyPos, rayDir, sunDir);
    float3 rayDir = HillaireSky::fromViewCoord(texcoord);
    
    // TODO: FOR DEBUG ONLY!
    float3 sunDir = normalize(ap.celestial.sunPosition);

    float tMax = planet.rayIntersectsAtmosphere(cameraSkyPos, rayDir);

    if (planetSurfaceEnabled) {
        float groundDist = planet.rayIntersectsGround(cameraSkyPos, rayDir);
        if (groundDist >= 0.0) tMax = groundDist;
    }

    float3 color = raymarchScattering(globalPos, cameraSkyPos, rayDir, sunDir, tMax);

    if (ap.timing.frameCounter > 0) {
        float3 color_last = texSkyView[globalPos];
        color = lerp(color_last, color, 0.0625);
    }

    color = clamp(color, 0.0, half.maxValue);
    texSkyView[globalPos] = color;

    float noise = BlueNoise::sampleAnimated1D(globalPos, 1, ap.timing.frameCounter);
    float3 rayViewDir = mul_rotate(ap.camera.view, rayDir);
    float4 clouds = renderClouds(rayViewDir, rayDir, noise);
    color = color * clouds.a + clouds.rgb;

    if (ap.timing.frameCounter > 0) {
        float3 color_last = texSkyViewClouds[globalPos];
        color = lerp(color_last, color, 0.0625);
    }

    color = clamp(color, 0.0, half.maxValue);
    texSkyViewClouds[globalPos] = color;
}
