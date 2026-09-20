import aperture;
import lib.common;
import lib.reblur;


static const float MaxAccumulatedFrames = 32.0;

// Raw noisy signal for this frame: rgb = color, a = normalized hit distance.
Texture2D<float4> texDiffuse_read;

Texture2D<float3> texReblurColor_read;
[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texReblurColor_write;

// r = luminance moment 1, g = luminance moment 2, b = accumulated frame count, a = accumulated hit distance.
Texture2D<float4> texReblurData_read;
[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texReblurData_write;

Texture2D<float> texReblurDepth_read;
[[vk::image_format("r32f")]]
RWTexture2D<float> texReblurDepth_write;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.screenSize)) return;

    float4 raw = texDiffuse_read[globalPos];
    float3 color_now = raw.rgb;
    float normHitDist_now = raw.a;

    float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;
    float depth = ap.depth[globalPos];

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 clipPosLast = ReBLUR::reprojectLast(clipPos);
    float2 texcoordLast = clipPosLast.xy * 0.5 + 0.5;

    float3 color_last = texReblurColor_read.Sample(apt_linearSampler, texcoordLast);
    float4 data_last = texReblurData_read.Sample(apt_linearSampler, texcoordLast);
    float frameCount = data_last.b;

    if (!all(saturate(texcoordLast) == texcoordLast)) {
        frameCount = 0.0;
    }
    else {
        float depthLast = texReblurDepth_read.Sample(apt_linearSampler, texcoordLast);

        clipPosLast.z = depthLast;
        float3 clipPosNext = ReBLUR::reprojectCurrent(clipPosLast);

        float depth_min = ap.camera.near / depth;
        float depth_max = depth_min;

        for (int i = 0; i < 8; i++) {
            float d = ap.camera.near / ap.depth[globalPos + sample_offsets[i]];
            depth_min = min(depth_min, d);
            depth_max = max(depth_max, d);
        }

        float testDepth = ap.camera.near / clipPosNext.z;
        if (clamp(testDepth, depth_min - 0.02, depth_max + 0.02) != testDepth) {
            frameCount = 0.0;
        }
    }

    frameCount = min(frameCount + 1.0, MaxAccumulatedFrames);
    float blendFactor = ap.timing.frameCounter > 0 ? (1.0 / frameCount) : 1.0;

    float3 color_out = lerp(color_last, color_now, blendFactor);
    color_out = clamp(color_out, 0.0, half.maxValue);

    float lum_now = luminance(color_now);
    float m1_out = lerp(data_last.r, lum_now, blendFactor);
    float m2_out = lerp(data_last.g, lum_now * lum_now, blendFactor);
    float hitDist_out = lerp(data_last.a, normHitDist_now, blendFactor);

    texReblurColor_write[globalPos] = color_out;
    texReblurData_write[globalPos] = float4(m1_out, m2_out, frameCount, hitDist_out);
    texReblurDepth_write[globalPos] = depth;
}
