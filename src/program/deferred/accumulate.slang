import aperture;
import lib.common;


static const float MaxAccumulatedFrames = 60.0;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuse_write;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuseHistory_write;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texSpecular_write;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texSpecularHistory_write;

[[vk::image_format("r8ui")]]
RWTexture2D<uint> texHistoryCounter_write;

Texture2D<float4> texDiffuse_read;
Texture2D<float4> texDiffuseHistory_read;
Texture2D<float4> texSpecular_read;
Texture2D<float4> texSpecularHistory_read;
Texture2D<uint> texHistoryCounter_read;


float3 reprojectLast(const in float3 clipPos) {
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float3 localPosLast = localPos + (ap.camera.position - ap.temporal.position);
    float3 viewPosLast = mul3(ap.temporal.view, localPosLast);
    return mul_project(ap.temporal.projection, viewPosLast);
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.screenSize)) return;

    float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;
    float depth = ap.depth[globalPos];

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 clipPosLast = reprojectLast(clipPos);
    float2 texcoordLast = clipPosLast.xy * 0.5 + 0.5;

    // gather
    float3 diffuse_now = texDiffuse_read[globalPos].rgb;
    float3 diffuse_last = texDiffuseHistory_read.Sample(apt_linearSampler, texcoordLast).rgb;

    float3 specular_now = texSpecular_read[globalPos].rgb;
    float3 specular_last = texSpecularHistory_read.Sample(apt_linearSampler, texcoordLast).rgb;

    // TODO: history counter and rejection
    uint historyCounter = texHistoryCounter_read.Sample(apt_nearestSampler, texcoordLast).r;

    if (!all(saturate(texcoordLast) == texcoordLast)) historyCounter = 0;

    if (!all(ap.camera.position == ap.temporal.position)) historyCounter = 0;
    if (!all(ap.camera.viewInv[2].xyz == ap.temporal.viewInv[2].xyz)) historyCounter = min(historyCounter, 8);

    // temporal blending
    historyCounter++;

    float3 diffuse_final, specular_final;
    if (ap.timing.frameCounter > 0) {
        diffuse_final = lerp(diffuse_last, diffuse_now, 1.0 / historyCounter);
        specular_final = lerp(specular_last, specular_now, 1.0 / historyCounter);
    }
    else {
        diffuse_final = diffuse_now;
        specular_final = specular_now;
    }

    texDiffuse_write[globalPos] = diffuse_final;
    texDiffuseHistory_write[globalPos] = diffuse_final;

    texSpecular_write[globalPos] = specular_final;
    texSpecularHistory_write[globalPos] = specular_final;

    texHistoryCounter_write[globalPos] = historyCounter;
}
