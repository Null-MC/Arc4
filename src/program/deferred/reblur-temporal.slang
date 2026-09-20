import aperture;
import lib.common;
import lib.reblur;


static const float MaxAccumulatedFrames = 32.0;

// Raw noisy signal for this frame: rgb = color, a = normalized hit distance.
Texture2D<float4> texDiffuse_read;

// Same-frame working buffers: consumed by the blur passes later this same frame.
[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texAccumColor_write;

// r = luminance moment 1, g = luminance moment 2, b = accumulated frame count, a = accumulated hit distance.
[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texAccumData_write;

// Cross-frame history: read is last frame's value, write goes to next frame's slot.
Texture2D<float3> texReblurColorHistory_read;
[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texReblurColorHistory_write;

Texture2D<float4> texReblurDataHistory_read;
[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texReblurDataHistory_write;

Texture2D<float> texReblurDepthHistory_read;
[[vk::image_format("r32f")]]
RWTexture2D<float> texReblurDepthHistory_write;


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

    float3 color_last = texReblurColorHistory_read.Sample(apt_linearSampler, texcoordLast);
    float4 data_last = texReblurDataHistory_read.Sample(apt_linearSampler, texcoordLast);
    float frameCount = data_last.b;

    if (depth <= 0.0 || !all(saturate(texcoordLast) == texcoordLast)) {
        frameCount = 0.0;
    }
    else {
        int2 historyPos = int2(texcoordLast * ap.game.screenSize);
        float3 expectedViewPos = mul_project(ap.temporal.projectionInv, clipPosLast);
        float expectedDistance = length(expectedViewPos);
        float closestDepthError = half.maxValue;

        // Select the historical surface whose view distance best matches the
        // reprojected current surface. This preserves valid history at edges.
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                int2 samplePos = historyPos + int2(x, y);
                if (any(samplePos < 0) || any(samplePos >= int2(ap.game.screenSize))) continue;

                float historyDepth = texReblurDepthHistory_read[samplePos];
                if (historyDepth <= 0.0) continue;

                float2 sampleTexcoord = (samplePos + 0.5) / ap.game.screenSize;
                float3 historyClipPos = float3(sampleTexcoord * 2.0 - 1.0, historyDepth);
                float historyDistance = length(mul_project(ap.temporal.projectionInv, historyClipPos));
                closestDepthError = min(closestDepthError, abs(historyDistance - expectedDistance));
            }
        }

        // Scale tolerance with distance so the test is stable at long range,
        // while still rejecting a foreground/background mismatch.
        float depthTolerance = max(0.01, expectedDistance * 0.01);
        if (closestDepthError > depthTolerance) {
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

    texReblurColorHistory_write[globalPos] = color_out;
    texReblurDataHistory_write[globalPos] = float4(m1_out, m2_out, frameCount, hitDist_out);
    texReblurDepthHistory_write[globalPos] = depth;

    texAccumColor_write[globalPos] = color_out;
    texAccumData_write[globalPos] = float4(m1_out, m2_out, frameCount, hitDist_out);
}
