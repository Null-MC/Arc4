import aperture;
import lib.common;


[[vk::image_format("rgba16f")]]
RWTexture2D<half3> texDiffuse_write;

Texture2D<half3> texDiffuse_read;

[[vk::image_format("rgba16f")]]
RWTexture2D<half3> texDiffuseHistory_write;

Texture2D<half3> texDiffuseHistory_read;

float3 reproject(float3 clipPos) {
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

    half3 color_now = texDiffuse_read[globalPos];

    // reproject
    float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;
    float depth = ap.opaqueDepth[globalPos];

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 clipPosLast = reproject(clipPos);
    float2 texcoordLast = clipPosLast.xy * 0.5 + 0.5;
    
    // sample previous frame
    half blendF = all(saturate(texcoordLast) == texcoordLast) ? 0.0125h : 1.0h;
    half3 color_last = texDiffuseHistory_read.Sample(apt_linearSampler, texcoordLast);
    color_now = ap.timing.frameCounter < 1 ? color_now : lerp(color_last, color_now, blendF);

    texDiffuse_write[globalPos] = color_now;
    texDiffuseHistory_write[globalPos] = color_now;
}
