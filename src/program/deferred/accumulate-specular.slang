import aperture;
import settings;
import lib.common;
import lib.pbr.material;


[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texSpecular_write;

[[vk::image_format("r8ui")]]
RWTexture2D<uint> texSpecularCounter_write;

Texture2D<float4> texSpecular_read;
Texture2D<float4> texSpecularHistory_read;
Texture2D<uint> texSpecularCounter_read;
Texture2D<float> texDepthHistory_read;

Texture2D<half4> texDeferSpecular;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float4 specular_now = texSpecular_read[globalPos];
    float3 specular_final;
    uint historyCounter;

    if (ap.timing.frameCounter > 0) {
        float depth_now = ap.depth[globalPos];

        float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
        float3 clipPos = float3(texcoord * 2.0 - 1.0, depth_now);
        float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
        float3 localPosX = mul3(ap.camera.viewInv, viewPos);

        viewPos += normalize(viewPos) * specular_now.a;
        float3 localPos = mul3(ap.camera.viewInv, viewPos);

        float3 localPosLast = localPos;
        // localPosLast += normalize(localPosLast) * specular_now.a;
        localPosLast += ap.camera.position - ap.temporal.position;

        float3 viewPosLast = mul3(ap.temporal.view, localPosLast);
        viewPosLast -= normalize(viewPosLast) * specular_now.a;
        float3 clipPosLast = mul_project(ap.temporal.projection, viewPosLast);
        float2 texcoordLast = clipPosLast.xy * 0.5 + 0.5;

        // reproject previous depth
        clipPosLast.z = texDepthHistory_read.Sample(apt_linearSampler, texcoordLast).r;
        viewPosLast = mul_project(ap.temporal.projectionInv, clipPosLast);
        localPosLast = mul3(ap.temporal.viewInv, viewPosLast);
        localPosLast -= ap.camera.position - ap.temporal.position;

        // history counter and rejection
        historyCounter = texSpecularCounter_read.Sample(apt_nearestSampler, texcoordLast).r;

        // reject if the motion between frames is too large
        if (length(localPosLast - localPosX) > 0.02 * length(localPosX) + 0.04) {
            texcoordLast = (floor(texcoordLast * ap.game.renderSize) + 0.5) / ap.game.renderSize;
            historyCounter = 0;
        }

        // reject if offscreen
        if (!all(saturate(texcoordLast) == texcoordLast)) historyCounter = 0;

        // reject if the camera has moved/rotated at all
        // if (!all(ap.camera.position == ap.temporal.position)) historyCounter = 0;
        // if (!all(ap.camera.viewInv[2].xyz == ap.temporal.viewInv[2].xyz)) historyCounter = min(historyCounter, 8);

        // temporal blending
        half4 specularMap = texDeferSpecular[globalPos];
        float roughness = getSpecularReader().roughness(specularMap);
        historyCounter = clamp(historyCounter, 0, int(120.0 * sqrt(roughness)) + 4);
        
        // historyCounter *= max(sqrt(roughness), 0.016);
        float3 specular_last = texSpecularHistory_read.Sample(apt_linearSampler, texcoordLast).rgb;
        specular_final = lerp(specular_last, specular_now.rgb, rcp(historyCounter + 1.0));
    }
    else {
        specular_final = specular_now.rgb;
        historyCounter = 0;
    }

    texSpecular_write[globalPos] = specular_final;
    texSpecularCounter_write[globalPos] = historyCounter;
}
