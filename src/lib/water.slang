public module water;

import aperture;
// import settings;
import lib.common;


// Texture2D<half> texWaterNoiseA;
Texture2D<half> texWaterNoiseB;
// Texture2D<half4> texWaterDisplacement;
SamplerState samplerWater;


float getWaterTime() {
    // if (userSettings.Accumulation) return 0.0;

    return ap.timing.timeElapsed;
}

float2 waveDx(const in float2 position, const in float2 direction, const in float frequency, const in float timeshift) {
    float x = dot(direction, position) * frequency + timeshift;
    float xMod = fmod(x, PI * 2.0);

    float wave = exp(sin(xMod) - 1.0);
    float dx = wave * cos(xMod);
    return float2(wave, -dx);
}

float3 GetWaveHeight(const in float3 position, const in float skyLight, const in uint iterations) {
    float iter = 0.0;           // this will help generating well distributed wave directions
    float weight = 1.0;         // weight in final sum for the wave, this will change every iteration
    float frequency = 0.65;      // frequency of the wave, this will change every iteration
    float timeMultiplier = 2.5; // time multiplier for the wave, this will change every iteration
    float sharpness = 2.0;

    float DRAG_MULT = 0.04;
    float wavePhaseShift = length(position) * 0.1;
    
    float3 wavePos = position;
    float weightSum = 0.0;
    float valueSum = 0.0;

    float time = getWaterTime();

    for (uint i = 0; i < iterations; i++) {
        float iterMod = fmod(iter, PI * 2.0);
        float2 p = float2(sin(iterMod), cos(iterMod));

        float2 octave = waveDx(wavePos.xz, p, frequency, time * timeMultiplier + wavePhaseShift);
        wavePos.xz += p * octave.y * weight * DRAG_MULT;

        valueSum += pow(octave.x, sharpness) * weight;
        weightSum += weight;

        iter += 1232.399963;
        timeMultiplier *= 1.07;
        frequency *= 1.28;
        weight *= 0.78;
        sharpness *= 1.02;
    }

    float heightDelta = (valueSum / max(weightSum, 0.000001));
    wavePos.y += heightDelta;

    float3 delta = wavePos;
    delta -= position;

    return delta;
}

float3 getWaterNormal(const in float3 localPos, const in float3 geo_normal) {
    float3 worldPos = localPos + ap.camera.position;

    float strength = texWaterNoiseB.Sample(samplerWater, worldPos.xz * 0.014).r;
    strength = strength * 0.25;

    // 1. Calculate the procedural height at the exact current pixel position
    float height = strength * GetWaveHeight(worldPos, 1.0, 28).y;

    // 2. Fetch screen-space derivatives of our world position and height
    float3 dX_pos = ddx(worldPos);
    float3 dY_pos = ddy(worldPos);
    
    float dX_height = ddx(height);
    float dY_height = ddy(height);

    // 3. Extrapolate position vectors containing the height perturbation
    // Rather than doing 2 extra height samples, we mathematically estimate how 
    // the height shifts relative to screen space pixel steps.
    float3 surf_dX = dX_pos + geo_normal * dX_height;
    float3 surf_dY = dY_pos + geo_normal * dY_height;

    // 4. Calculate the cross product of our surface derivatives to find the true normal.
    // The cross ordering determines orientation; assuming a Y-up plane, this matches.
    float3 computedNormal = cross(surf_dX, surf_dY);
    return normalize(computedNormal);
}
