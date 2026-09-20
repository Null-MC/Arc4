import aperture;
import lib.common;
import lib.reblur;


static const float StabilizationMaxFrames = 4.0;

Texture2D<float3> texPostBlur_read;

Texture2D<float3> texReblurStable_read;
[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texReblurStable_write;

Texture2D<float4> texReblurData_read;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float3 current = texPostBlur_read[globalPos];
    float depth = ap.depth[globalPos];

    if (depth > 0.0 && ap.timing.frameCounter > 0) {
        float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
        float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
        float3 clipPosLast = ReBLUR::reprojectLast(clipPos);
        float2 texcoordLast = clipPosLast.xy * 0.5 + 0.5;

        if (all(saturate(texcoordLast) == texcoordLast)) {
            float3 historyColor = texReblurStable_read.Sample(apt_linearSampler, texcoordLast);

            // Clamp history to the local neighborhood of the freshly denoised signal to kill flicker
            // without reintroducing the lag a naive temporal blend would cause.
            float3 neighborMin = current;
            float3 neighborMax = current;
            for (int i = 0; i < 8; i++) {
                float3 tap = texPostBlur_read[globalPos + sample_offsets[i]];
                neighborMin = min(neighborMin, tap);
                neighborMax = max(neighborMax, tap);
            }

            historyColor = clamp(historyColor, neighborMin, neighborMax);

            float frameCount = texReblurData_read[globalPos].b;
            float blend = saturate(1.0 / min(max(frameCount, 1.0), StabilizationMaxFrames));

            current = lerp(historyColor, current, blend);
        }
    }

    texReblurStable_write[globalPos] = current;
}
