public module sky_shared;

import aperture;
import settings;
import lib.common;


namespace HillaireSky {

    ConstantBuffer<PlanetAtmosphere, ScalarDataLayout> planet;
    ConstantBuffer<SkyParameters, ScalarDataLayout> sky;

}


static const float3 groundAlbedo = 0.3;
static const bool planetSurfaceEnabled = true;

static const float Sky_MinLight = 0.0;//0.08;

static const float3 SunColor = pow(float3(1.0, 0.95, 0.9), 2.2) * 2000.0;
static const float3 MoonColor = pow(float3(0.5, 0.5, 0.55), 2.2) * 2.2;


struct PlanetAtmosphere {
    float RadiusGround_KM;
    float RadiusAtmosphere_KM;

    float getNormalizedHeight(const in float worldHeight_KM) {
        return unmix(RadiusGround_KM, RadiusAtmosphere_KM, worldHeight_KM);
    }

    float getWorldHeight(const in float normalizedHeight) {
        return lerp(RadiusGround_KM, RadiusAtmosphere_KM, normalizedHeight);
    }

    float rayIntersectsGround(const in float3 pos, const in float3 sunDir) {
        return rayIntersectSphere(pos, sunDir, RadiusGround_KM);
    }

    float rayIntersectsAtmosphere(const in float3 pos, const in float3 sunDir) {
        return rayIntersectSphere(pos, sunDir, RadiusAtmosphere_KM);
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

        return skyPos_KM;
    }
};

struct SkyParameters {
    // Constant base properties at sea level (Earth)
    float3 BETA_RAYLEIGH_BASE;
    float  BETA_MIE_BASE_SCA;
    float  BETA_MIE_BASE_ABS;

    // Default distribution scale heights (in meters)
    float H_R_DEFAULT;
    float H_M_DEFAULT;

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
        // MIE (Aerosols, Dust, Fog)
        // ----------------------------------------------------
        // Weather scale: Fog lowers the scale height, trapping particles near the ground
        float humidity = saturate(userSettings.Sky_Humidity);
        float fog = saturate(userSettings.Sky_FogIntensity);
        float wetAerosol = lerp(1.0, 16.0, pow2(humidity));
        float fogAerosol = lerp(1.0, 8.0, pow2(fog));
        float mieScaleHeight = lerp(H_M_DEFAULT, 0.25, userSettings.Sky_FogIntensity);
        float mieDensity = exp(-max(altitude_KM, 0.0) / mieScaleHeight);

        // Weather scale: Turbidity increases overall aerosol count dramatically
        float mieScatteringScalar = BETA_MIE_BASE_SCA * userSettings.Sky_Turbidity * wetAerosol * fogAerosol;
        outSample.mieScattering = float3(mieScatteringScalar * mieDensity);

        // Handle absorption (clean aerosols absorb a bit, pollution/sand absorbs a lot)
        float3 pollution = saturate(float3(userSettings.Sky_PollutionColor_R, userSettings.Sky_PollutionColor_G, userSettings.Sky_PollutionColor_B));
        float3 mieAbsorptionBase = float3(BETA_MIE_BASE_ABS) * (1.0 + 4.0 * pollution);
        float3 mieAbsorption = mieAbsorptionBase * userSettings.Sky_Turbidity * wetAerosol * fogAerosol * mieDensity;

        // ----------------------------------------------------
        // TOTAL EXTINCTION
        // ----------------------------------------------------
        // Extinction is everything that strips light away from the ray path
        // Note: Ozone absorption would be added to this total extinction
        outSample.extinction = outSample.rayleighScattering + outSample.mieScattering + mieAbsorption;
    }
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
