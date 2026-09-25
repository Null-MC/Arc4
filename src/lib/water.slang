public module water;

import aperture;
import settings;


Texture2D<half> texWaterNoiseA;
Texture2D<half> texWaterNoiseB;
Texture2D<half4> texWaterDisplacement;
SamplerState samplerWater;


/// This is a value going from 0 to 1 that defines the amount of vertex offset happening on the object for both noise textures. It’s basically a global controller for the vertex offset. Also useful to adjust the vertex offset when scaling up the water mesh, as that will exaggerate the vertex displacement.
static const float offsetAmount = 0.011;
    
// speed_X, speed_Y, contrast, contribution
static const float4 noiseAProperties = float4(0.0, 0.15, 0.63, -1.51);
static const float4 noiseBProperties = float4(0.0, -0.06, 0.65, 0.54);

/// speed_X, speed_Y, contribution
static const float4 displacementProperties = float4(0.0, 0.0, 0.04, 0.04);


float getWaterTime() {
    if (userSettings.Accumulation) return 0.0;

    return ap.timing.timeElapsed;
}

float sampleNoiseTexture(float2 pos, Texture2D<half> tex, float4 props, float2 displ) {
    float2 uv = pos + displ + getWaterTime() * props.xy;
    float value = tex.Sample(samplerWater, uv).r;
    
    // Replicate Harry's contrast curve and contribution scalar
    value = (saturate(lerp(0.5, value, props.z)) * 2.0 - 1.0) * props.w;
    return value;
}

float noiseOffset(float2 pos) {
    float2 displUV = pos + getWaterTime() * displacementProperties.xy;
    float2 displ = texWaterDisplacement.Sample(samplerWater, displUV).xy;
    displ = ((displ * 2.0) - 1.0) * displacementProperties.z;

    float noiseA = sampleNoiseTexture(pos, texWaterNoiseA, noiseAProperties, displ);
    float noiseB = sampleNoiseTexture(pos, texWaterNoiseB, noiseBProperties, displ);
    
    return noiseA * noiseB;
}

float3 getWaterNormal(const in float3 localPos, const in float3 geo_normal) {
    float3 worldPos = localPos + ap.camera.position;

    // 1. Calculate the procedural height at the exact current pixel position
    float height = noiseOffset(worldPos.xz) * offsetAmount;

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
