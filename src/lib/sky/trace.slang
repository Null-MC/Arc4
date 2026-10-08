public module sky_trace;

import aperture;
import settings;
import lib.noise.ign;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.multiscatter;
import lib.sky.clouds;


extension PlanetBuffer {

    // float traceCloudShadow(const in float3 localPos, const in float3 skyLightDir, const in float dither) {
    //     // float shadowDither = BlueNoise::sampleAnimated1D(globalPos, 0, ap.timing.frameCounter);
    //     float3 skyPos = getSkyPosition(localPos);

    //     float cloudMinDist = rayIntersectSphere(skyPos, skyLightDir, RadiusGround_KM + cloud_height*0.001);
    //     float cloudMaxDist  = rayIntersectSphere(skyPos, skyLightDir, RadiusGround_KM + maxHeight*0.001);

    //     float cloudDistNear = min(cloudMinDist, cloudMaxDist) * 1000.0;
    //     float cloudDistFar = max(cloudMinDist, cloudMaxDist) * 1000.0;

    //     float3 trace_localStart = localPos + skyLightDir * cloudDistNear;
    //     float3 trace_localEnd = localPos + skyLightDir * cloudDistFar;

    //     const int rayMarchSteps = 6;
    //     float cloudShadow = 0.0;

    //     for (int i = 0; i < rayMarchSteps; i++) {
    //         float stepF = (i + dither) / rayMarchSteps;
    //         float3 trace_localPos = lerp(trace_localStart, trace_localEnd, stepF);
    //         float3 trace_skyPos = getSkyPosition(trace_localPos);
    //         cloudShadow += getCloudDensity(trace_localPos, trace_skyPos, 0);
    //     }

    //     cloudShadow = lerp(1.0, exp(-cloudShadow * cloudDensity * 1700.0/rayMarchSteps), lerp(CloudShadowStrength, 1.0, ap.world.rainStrength));

    //     return cloudShadow;
    // }

    float traceCloudShadow(const in float3 skyPos, const in float3 skyLightDir, const in float dither) {
        // float shadowDither = BlueNoise::sampleAnimated1D(globalPos, 0, ap.timing.frameCounter);
        // float3 skyPos = getSkyPosition(localPos);

        float cloudMinDist = rayIntersectSphere(skyPos, skyLightDir, RadiusGround_KM + cloud_height*0.001);
        float cloudMaxDist  = rayIntersectSphere(skyPos, skyLightDir, RadiusGround_KM + maxHeight*0.001);

        float cloudDistNear = min(cloudMinDist, cloudMaxDist);
        float cloudDistFar = max(cloudMinDist, cloudMaxDist);

        if (cloudDistNear < 0) return 0.0;

        float3 trace_skyStart = skyPos + skyLightDir * cloudDistNear;
        float3 trace_skyEnd = skyPos + skyLightDir * cloudDistFar;

        const int rayMarchSteps = 6;
        float cloudShadow = 0.0;

        for (int i = 0; i < rayMarchSteps; i++) {
            float stepF = (i + dither) / rayMarchSteps;
            // float3 trace_localPos = lerp(trace_localStart, trace_localEnd, stepF);
            // float3 trace_skyPos = getSkyPosition(trace_localPos);
            float3 trace_skyPos = lerp(trace_skyStart, trace_skyEnd, stepF);
            cloudShadow += getCloudDensity(trace_skyPos, 0);
        }

        cloudShadow = lerp(1.0, exp(-cloudShadow * cloudDensity * 1700.0/rayMarchSteps), lerp(CloudShadowStrength, 1.0, ap.world.rainStrength));

        return cloudShadow;
    }

}

extension SkyBuffer {

    void raymarchScattering(out float3 scattering, out float3 transmittance, uint2 globalPos, float3 skyPos, float3 rayDir, float3 sunDir, float tMax, int numScatteringSteps) {
        float cosTheta = dot(rayDir, sunDir);
        
        float miePhaseValue_sun = getMiePhase(cosTheta);
        float rayleighPhaseValue_sun = getRayleighPhase(cosTheta);

        float miePhaseValue_moon = getMiePhase(-cosTheta);
        float rayleighPhaseValue_moon = getRayleighPhase(-cosTheta);

        float dither = IGN::getAnimated(globalPos);
        float stepSize = tMax / numScatteringSteps;

        // float3 scattering = 0.0;
        // float3 transmittance = 1.0;
        scattering = 0.0;
        transmittance = 1.0;

        for (int i = 0; i < numScatteringSteps; i++) {
            float t = (i + dither) * stepSize;
            float3 trace_skyPos = skyPos + t*rayDir;
            
            AtmosphereSample skySample;
            float altitude_KM = planet.getSkyAltitude(trace_skyPos);
            // altitude_KM = max(altitude_KM, 1e-6);
            sky.Sample(altitude_KM, skySample);

            float3 skyLightDir = normalize(ap.celestial.position);
            float cloudShadow = planet.traceCloudShadow(trace_skyPos, skyLightDir, dither);

            float3 sampleTransmittance = exp(-stepSize * skySample.extinction);

            float3 sunTransmittanceLux = planet.sampleTransmit(trace_skyPos, sunDir) * SunColor * cloudShadow;
            float3 moonTransmittanceLux = planet.sampleTransmit(trace_skyPos, -sunDir) * MoonColor * cloudShadow;

            float3 psiMS = planet.sampleMultiScatter(trace_skyPos, sunDir) + Sky_MinLight;
            //vec3 psiMS_moon = getValFromMultiScattLUT(texSkyMultiScatter, trace_skyPos, sunDir);

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

        // return scattering;
    }

}
