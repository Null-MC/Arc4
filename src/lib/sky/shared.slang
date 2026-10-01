public module sky_shared;

import aperture;
import settings;
import lib.common;


static const float3 groundAlbedo = 0.3;
static const bool planetSurfaceEnabled = true;

static const float Sky_MinLight = 0.0;//0.08;

static const float3 SunColor = 2000.0;// * transformer.fromGamma(1.0);
static const float3 MoonColor = 0.2;// * transformer.fromGamma(1.0);


extension PlanetBuffer {
    float getNormalizedHeight(const in float worldHeight_KM) {
        return unmix(RadiusGround_KM, RadiusAtmosphere_KM, worldHeight_KM);
    }

    float getWorldHeight(const in float normalizedHeight) {
        return lerp(RadiusGround_KM, RadiusAtmosphere_KM, normalizedHeight);
    }

    float rayIntersectsGround(const in float3 pos, const in float3 rayDir) {
        return rayIntersectSphere(pos, rayDir, RadiusGround_KM);
    }

    float rayIntersectsAtmosphere(const in float3 pos, const in float3 rayDir) {
        return rayIntersectSphere(pos, rayDir, RadiusAtmosphere_KM);
    }

    // Returns the altitude in KM above the planet surface.
    float getSkyAltitude(const in float3 skyPos) {
        return length(skyPos) - RadiusGround_KM;
    }

    float3 getSkyPosition(const in float3 localPos) {
        // Camera and local positions are meters; the planet model uses kilometers.
        float3 skyPos_KM = localPos * 0.001;
        float cameraAltitude_KM = (ap.camera.position.y - userSettings.SeaLevel) * 0.001;
        skyPos_KM.y += cameraAltitude_KM + RadiusGround_KM;

        skyPos_KM.y = max(skyPos_KM.y, RadiusGround_KM + 0.00002);

        return skyPos_KM;
    }
};

extension SkyBuffer {
    void Sample(const in float altitude_KM, out AtmosphereSample outSample) {
        // ----------------------------------------------------
        // RAYLEIGH (Air Molecules)
        // ----------------------------------------------------
        // Weather scale: Pressure compresses or expands base density
        float3 rayleighSeaLevel = BETA_RAYLEIGH_BASE * userSettings.Sky_BarometricPressure;
        
        // Slight shift in scale height based on pressure/temperature extremes
        float rayleighScaleHeight = H_R_DEFAULT * (1.0 + (userSettings.Sky_BarometricPressure - 1.0) * 0.1);
        float rayleighDensity = exp(-max(altitude_KM, 0.0) / rayleighScaleHeight);

        outSample.rayleighScattering = rayleighSeaLevel * rayleighDensity;


        // ----------------------------------------------------
        // MIE - LAYER A: PLANETARY AEROSOLS (Global Haze/Dust)
        // ----------------------------------------------------
        // Humidity swells default global aerosols slightly
        float wetAerosol = lerp(1.0, 4.0, pow2(userSettings.Sky_Humidity));
        float planetaryMieDensity = exp(-max(altitude_KM, 0.0) / H_M_DEFAULT);
        
        float planetaryScatteringScalar = BETA_MIE_BASE_SCA * userSettings.Sky_Turbidity * wetAerosol;
        float3 planetaryMieScattering = float3(planetaryScatteringScalar * planetaryMieDensity);


        // ----------------------------------------------------
        // MIE - LAYER B: GROUND FOG BLANKET (Localized Dense Fog)
        // ----------------------------------------------------
        float fogIntensity3 = pow3(userSettings.Sky_FogIntensity);

        // Compute fog envelope properties based on slider intensity
        // Max height dynamically scales up to 250 meters (0.25 KM)
        float fogMaxHeight_KM = lerp(0.01, 0.25, userSettings.Sky_FogIntensity);
        
        // Falloff softness at the top boundary edge of the fog bank
        float fogTopSoftness_KM = 0.03; 
        
        // Create a physical boundary envelope using smoothstep
        float fogEnvelope = saturate(1.0 - smoothstep(fogMaxHeight_KM - fogTopSoftness_KM, fogMaxHeight_KM, altitude_KM));
        
        // Internal distribution: Apply rapid exponential decay inside the blanket so it is thickest at ground level
        float fogInternalFalloff = exp(-max(altitude_KM, 0.0) / 0.06);
        float groundFogDensity = fogEnvelope * fogInternalFalloff;

        // Non-linear perceptual scaling: High fog slider values yield exponential density increases
        // Boosted up to a 128x multiplier for heavy, murky opaque fog conditions
        float fogScatteringScalar = BETA_MIE_BASE_SCA * lerp(0.0, 12800.0, fogIntensity3);
        float3 groundFogMieScattering = float3(fogScatteringScalar * groundFogDensity);

        // Combine planetary dust and dense ground fog into final Mie scattering
        outSample.mieScattering = planetaryMieScattering + groundFogMieScattering;


        // ----------------------------------------------------
        // 4. MIE ABSORPTION & TOTAL EXTINCTION
        // ----------------------------------------------------
        // Pollution factors handle coloring/light-loss for industrial settings or dust storms
        float3 pollution = saturate(float3(userSettings.Sky_PollutionColor_R, userSettings.Sky_PollutionColor_G, userSettings.Sky_PollutionColor_B));
        float3 mieAbsorptionBase = float3(BETA_MIE_BASE_ABS) * (1.0 + 4.0 * pollution);

        // Planetary absorption maps to global planetary layer
        float3 planetaryMieAbsorption = mieAbsorptionBase * userSettings.Sky_Turbidity * wetAerosol * planetaryMieDensity;
        
        // Fog layer absorption tracks the ground fog profile to maintain proper volumetric shadows inside the fog bank
        float3 groundFogMieAbsorption = mieAbsorptionBase * (lerp(0.0, 128.0, fogIntensity3) * groundFogDensity);
        
        float3 totalMieAbsorption = planetaryMieAbsorption + groundFogMieAbsorption;

        // Extinction represents all accumulated light scattered away or absorbed along the ray path
        outSample.extinction = outSample.rayleighScattering + outSample.mieScattering + totalMieAbsorption;
    }
    
    // public void trace(out float3 scattering, out float3 transmittance, const in float3 origin, const in float3 rayDir, const in float rayDist, const in int stepCount) {
    //     scattering = 0.0;
    //     transmittance = 1.0;

    //     for (int i = 0; i < stepCount; i++) {
    //         float3 traceSkyPos = skyPos + i * stepDist * skyLightDir;

    //         AtmosphereSample skySample;
    //         float altitude_KM = planet.getSkyAltitude(traceSkyPos);
    //         sky.Sample(altitude_KM, skySample);

    //         float3 sampleTransmittance = exp(-stepDist * skySample.extinction);

    //         // Integrate within each segment.
    //         // float3 scatteringNoPhase = skySample.rayleighScattering + skySample.mieScattering;
    //         // float3 scatteringF = (scatteringNoPhase - scatteringNoPhase * sampleTransmittance) / skySample.extinction;
    //         // lumFactor += transmittance * scatteringF;

    //         float3 sunLight = planet.sampleTransmit(traceSkyPos, sunDir) * SunColor;
    //         float3 moonLight = planet.sampleTransmit(traceSkyPos, moonDir) * MoonColor;

    //         float3 inScattering = skySample.mieScattering * (miePhase_sun * sunLight + miePhase_moon * moonLight) + Sky_MinLight;

    //         // Integrated scattering within path segment.
    //         float3 scatteringIntegral = (inScattering - inScattering * sampleTransmittance) / skySample.extinction;

    //         scattering += scatteringIntegral * transmittance;
    //         transmittance *= sampleTransmittance;
    //     }
    // }
};

struct AtmosphereSample {
    float3 rayleighScattering;
    float3 mieScattering;
    float3 extinction;
};

float safeacos(const in float x) {
    return acos(clamp(x, -1.0, 1.0));
}

float getMiePhase(float cosTheta) {
    // ----------------------------------------------------
    // 3. MIE ASYMMETRY (Phase Function Profile)
    // ----------------------------------------------------
    // Weather scale: High humidity makes particles expand into water droplets, 
    // pinching light tightly forward around the sun disk.
    float mieAsymmetryG = lerp(0.76, 0.98, pow2(userSettings.Sky_Humidity));

    return CornetteShanksPhaseFunction(mieAsymmetryG, cosTheta);
}

float getRayleighPhase(float cosTheta) {
    const float k = 3.0 / (16.0*PI);
    return k * (1.0 + pow2(cosTheta));
}

float CornetteShanksPhaseFunction(float g, float cosTheta) {
    float g2 = g * g;
    float num = 3.0 * (1.0 - g2) * (1.0 + cosTheta * cosTheta);
    float den = 2.0 * (2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
    return num / (4.0 * PI * den);
}

// From https://gamedev.stackexchange.com/questions/96459/fast-ray-sphere-collision-code.
float rayIntersectSphere(const in float3 center, const in float3 direction, const in float radius) {
    float b = dot(center, direction);
    float c = dot(center, center) - pow2(radius);
    if (c > 0.0f && b > 0.0) return -1.0;

    float discr = b*b - c;
    if (discr < 0.0) return -1.0;

    // Special case: inside sphere, use far discriminant
    if (discr > b*b) return (-b + sqrt(discr));
    return -b - sqrt(discr);
}
