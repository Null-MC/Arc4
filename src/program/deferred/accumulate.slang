import aperture;
import lib.common;


static const float MaxBlendFrames = 64;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuse_write;

Texture2D<float3> texDiffuse_read;

[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texDiffuseHistory_write;

Texture2D<float4> texDiffuseHistory_read;

[[vk::image_format("r32f")]]
RWTexture2D<float> texDepthHistory_write;

Texture2D<float> texDepthHistory_read;


float3 reproject_last(float3 clipPos) {
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float3 localPosLast = localPos + (ap.camera.position - ap.temporal.position);
    float3 viewPosLast = mul3(ap.temporal.view, localPosLast);
    return mul_project(ap.temporal.projection, viewPosLast);
}

float3 reproject_current(float3 clipPosLast) {
    float3 viewPosLast = mul_project(ap.temporal.projectionInv, clipPosLast);
    float3 localPosLast = mul3(ap.temporal.viewInv, viewPosLast);

    float3 localPos = localPosLast - (ap.camera.position - ap.temporal.position);
    float3 viewPos = mul3(ap.camera.view, localPos);
    return mul_project(ap.camera.projection, viewPos);
}

static const int2 sample_offsets[] = {
    int2(-1,-1),
    int2( 0,-1),
    int2( 1,-1),
    int2(-1, 0),
    int2( 1, 0),
    int2(-1, 1),
    int2( 0, 1),
    int2( 1, 1),
};


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.screenSize)) return;

    float3 color_now = texDiffuse_read[globalPos];

    // reproject
    float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;
    float depth = ap.depth[globalPos];

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 clipPosLast = reproject_last(clipPos);
    float2 texcoordLast = clipPosLast.xy * 0.5 + 0.5;

    // sample previous frame
    float4 color_last = texDiffuseHistory_read.Sample(apt_linearSampler, texcoordLast);
    float counter = color_last.a;
    
    if (!all(saturate(texcoordLast) == texcoordLast)) counter = 0.0;
    else {
        float depthLast = texDepthHistory_read.Sample(apt_linearSampler, texcoordLast);

        // float3 clipPosLast = float3(clipPosLast.xy, depthLast);
        clipPosLast.z = depthLast;
        float3 clipPosNext = reproject_current(clipPosLast);
        // float2 texcoordNext = clipPosNext.xy * 0.5 + 0.5;


        // TODO: neighborhood depth test
        float depth_min = ap.camera.near / depth;
        float depth_max = depth_min;

        for (int i = 0; i < 8; i++) {
            float in1 = ap.camera.near / ap.depth[globalPos + sample_offsets[i]];

            depth_min = min(depth_min, in1);
            depth_max = max(depth_max, in1);
        }

        float shit = ap.camera.near / clipPosNext.z;
        if (clamp(shit, depth_min-0.02, depth_max+0.02) != shit) counter = 0.0;
    }

    if (ap.timing.frameCounter > 0) {
        float blendF = 1.0 / clamp(counter++, 1.0, MaxBlendFrames);
        color_now = lerp(color_last.rgb, color_now, blendF);
    }

    color_now = clamp(color_now, 0.0, half.maxValue);
    
    texDiffuse_write[globalPos] = color_now;
    texDiffuseHistory_write[globalPos] = float4(color_now, counter);
    texDepthHistory_write[globalPos] = depth;
}
