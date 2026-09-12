import aperture;
import lib.common;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.multiscatter;
import lib.noise.blue;
import lib.bayer;
import lib.ign;


extern static const int BufferWidth;
extern static const int BufferHeight;
static const float mulScattSteps = 20.0;
static const int sampleCount = 8;

[[vk::image_format("rgba16f")]]
RWTexture2D<half3> texSkyMultiScatter;


// float3 getSphericalDir(float theta, float phi) {
//     float cosPhi = cos(phi);
//     float sinPhi = sin(phi);
//     float cosTheta = cos(theta);
//     float sinTheta = sin(theta);
//     return float3(sinPhi*sinTheta, cosPhi, sinPhi*cosTheta);
// }

float3 sampleCosineWeightedHemisphere(const in float2 u) {
    float r = sqrt(u.x);
    float theta = (2.0 * PI) * u.y;
    return float3(r * cos(theta), r * sin(theta), sqrt(max(0.0, 1.0 - u.x)));
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    float2 uv = (globalPos.xy + 0.5) / float2(BufferWidth, BufferHeight);
    if (!all(globalPos < uint2(BufferWidth, BufferHeight))) return;

    var planet = HillaireSky::currentPlanet();
    var sky = HillaireSky::currentSky();

    float3 pos, sunDir;
    HillaireSky::fromMultiScatterCoord(uv, planet, pos, sunDir);
    
    float3 lumTotal = 0.0;
    float3 fms = 0.0;

    for (int i = 0; i < sampleCount; i++) {
        float time = ap.timing.frameCounter * sampleCount + i;
        float dither = InterleavedGradientNoiseTime(globalPos, time);

        float2 rayNoise = getAnimatedBlueNoise(globalPos, i, ap.timing.frameCounter);
        float3 rayDir = sampleCosineWeightedHemisphere(rayNoise);

        float atmoDist = planet.rayIntersectsAtmosphere(pos, rayDir);
        float groundDist = planet.rayIntersectsGround(pos, rayDir);

        float tMax = atmoDist;
        if (groundDist > 0.0) {
            tMax = groundDist;
        }

        float VoL_sun = dot(rayDir, sunDir);
        float miePhase_sun = getMiePhase(VoL_sun);
        float rayleighPhase_sun = getRayleighPhase(VoL_sun);

        float VoL_moon = -VoL_sun;
        float miePhase_moon = getMiePhase(VoL_moon);
        float rayleighPhase_moon = getRayleighPhase(VoL_moon);

        float3 lum = 0.0, lumFactor = 0.0, transmittance = 1.0;

        float stepSize = tMax / mulScattSteps;
        float t = 0.0;

        for (int stepI = 0; stepI < mulScattSteps; stepI++) {
            float t = (stepI + dither) * stepSize;

            float3 newPos = pos + t*rayDir;

            AtmosphereSample skySample;
            float altitude_KM = planet.getSkyAltitude(newPos);
            sky.Sample(altitude_KM, skySample);

            float3 sampleTransmittance = exp(-stepSize * skySample.extinction);

            // Integrate within each segment.
            float3 scatteringNoPhase = skySample.rayleighScattering + skySample.mieScattering;
            float3 scatteringF = scatteringNoPhase * ((1.0 - sampleTransmittance) / max(skySample.extinction, 1e-5));
            lumFactor += transmittance * scatteringF;

            float3 sunTransmittanceLux = HillaireSky::sampleTransmit(planet, newPos, sunDir) * SunColor;
            float3 moonTransmittanceLux = HillaireSky::sampleTransmit(planet, newPos, -sunDir) * MoonColor;

            float3 rayleighInScattering_sun = skySample.rayleighScattering * rayleighPhase_sun;
            float3 mieInScattering_sun = skySample.mieScattering * miePhase_sun;

            float3 rayleighInScattering_moon = skySample.rayleighScattering * rayleighPhase_moon;
            float3 mieInScattering_moon = skySample.mieScattering * miePhase_moon;

            float3 inScattering = (rayleighInScattering_sun + mieInScattering_sun) * sunTransmittanceLux
                                + (rayleighInScattering_moon + mieInScattering_moon) * moonTransmittanceLux
                                + Sky_MinLight;

            // Integrated scattering within path segment.
            float3 scatteringIntegral = inScattering * ((1.0 - sampleTransmittance) / max(skySample.extinction, 1e-5));

            lum += scatteringIntegral * transmittance;
            transmittance *= sampleTransmittance;
        }

        if (groundDist > 0.0) {
            float3 hitPos = pos + groundDist*rayDir;
            
            if (dot(pos, sunDir) > 0.0) {
                hitPos = normalize(hitPos) * planet.RadiusGround_KM;
                lum += transmittance * groundAlbedo * HillaireSky::sampleTransmit(planet, hitPos, sunDir);
            }
        }

        fms += lumFactor;
        lumTotal += lum;
    }

    const float invSamples = rcp(sampleCount);
    fms = min(fms * invSamples, 0.999);
    lumTotal *= invSamples;

    half3 color_new = half3(lumTotal / max(1.0 - fms, 1e-8));

    half3 color = texSkyMultiScatter[globalPos];
    color = ap.timing.frameCounter < 1 ? color_new : lerp(color, color_new, half3(0.0625));
    texSkyMultiScatter[globalPos] = color;
}
