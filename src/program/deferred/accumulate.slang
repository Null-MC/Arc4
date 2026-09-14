import aperture;
import lib.common;


static const float MaxBlendFrames = 64;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuse_write;

Texture2D<float3> texDiffuse_read;

[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texDiffuseHistory_write;

Texture2D<float4> texDiffuseHistory_read;

float3 reproject(float3 clipPos) {
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float3 localPosLast = localPos + (ap.camera.position - ap.temporal.position);
    float3 viewPosLast = mul3(ap.temporal.view, localPosLast);
    return mul_project(ap.temporal.projection, viewPosLast);
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
    float depth = ap.opaqueDepth[globalPos];

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 clipPosLast = reproject(clipPos);
    float2 texcoordLast = clipPosLast.xy * 0.5 + 0.5;

    // sample previous frame
    float4 color_last = texDiffuseHistory_read.Sample(apt_linearSampler, texcoordLast);
    float counter = color_last.a;
    
    if (!all(saturate(texcoordLast) == texcoordLast)) counter = 0.0;
    else {
        // TODO: neighborhood depth test
        // float depth_min = depth;
        // float depth_max = depth;

        // for (int i = 0; i < 8; i++) {
        //     float in1 = ap.opaqueDepth[globalPos + sample_offsets[i]];

        //     depth_min = min(depth_min, in1);
        //     depth_max = max(depth_max, in1);
        // }

        // float depthLast = ;
        // if (clamp(depthLast, depth_min, depth_max) != depthLast) counter = 0.0;
    }

    float blendF = 1.0 / clamp(counter++, 1.0, MaxBlendFrames);

    if (ap.timing.frameCounter > 0) {
        color_now = lerp(color_last.rgb, color_now, blendF);
    }

    texDiffuse_write[globalPos] = color_now;
    texDiffuseHistory_write[globalPos] = float4(color_now, counter);
}
