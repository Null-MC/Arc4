import aperture;
import settings;
import lib.common;
import lib.pbr.material;


[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuse_write;

[[vk::image_format("r8ui")]]
RWTexture2D<uint> texDiffuseCounter_write;

Texture2D<float4> texDiffuse_read;
Texture2D<float4> texDiffuseHistory_read;
Texture2D<uint> texDiffuseCounter_read;
Texture2D<float> texDepthHistory_read;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float3 diffuse_now = texDiffuse_read[globalPos].rgb;
    float3 diffuse_final;
    uint historyCounter;
    
    if (ap.timing.frameCounter > 0) {
        float depth_now = ap.depth[globalPos];

        float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
        float3 clipPos = float3(texcoord * 2.0 - 1.0, depth_now);
        float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
        float3 localPos = mul3(ap.camera.viewInv, viewPos);

        float3 localPosLast = localPos + (ap.camera.position - ap.temporal.position);
        float3 viewPosLast = mul3(ap.temporal.view, localPosLast);
        float3 clipPosLast = mul_project(ap.temporal.projection, viewPosLast);
        float2 texcoordLast = clipPosLast.xy * 0.5 + 0.5;

        // reproject previous depth
        clipPosLast.z = texDepthHistory_read.Sample(apt_linearSampler, texcoordLast).r;
        viewPosLast = mul_project(ap.temporal.projectionInv, clipPosLast);
        localPosLast = mul3(ap.temporal.viewInv, viewPosLast);
        localPosLast -= ap.camera.position - ap.temporal.position;

        // history counter and rejection
        historyCounter = texDiffuseCounter_read.Sample(apt_nearestSampler, texcoordLast).r;

        // reject if the motion between frames is too large
        if (length(localPosLast - localPos) > 0.02 * length(localPos)) {
            texcoordLast = (floor(texcoordLast * ap.game.renderSize) + 0.5) / ap.game.renderSize;
            historyCounter = 0;
        }

        // reject if offscreen
        if (!all(saturate(texcoordLast) == texcoordLast)) historyCounter = 0;

        // reject if the camera has moved/rotated at all
        // if (!all(ap.camera.position == ap.temporal.position)) historyCounter = 0;
        // if (!all(ap.camera.viewInv[2].xyz == ap.temporal.viewInv[2].xyz)) historyCounter = min(historyCounter, 8);

        // temporal blending
        historyCounter = clamp(historyCounter, 0, 120);

        float3 diffuse_last = texDiffuseHistory_read.Sample(apt_linearSampler, texcoordLast).rgb;
        diffuse_final = lerp(diffuse_last, diffuse_now, rcp(historyCounter + 1.0));
    }
    else {
        diffuse_final = diffuse_now;
        historyCounter = 0;
    }

    texDiffuse_write[globalPos] = diffuse_final;
    texDiffuseCounter_write[globalPos] = historyCounter;
}
