import aperture;
import lib.common;
import lib.reblur;
import lib.octohedral;
import lib.noise.blue;


static const float BlurRadiusPixels = 10.0;
static const float MaxAccumulatedFrames = 64.0;
static const int TapCount = 6;

Texture2D<float3> texBlur_read;
Texture2D<float4> texAccumData_read;
Texture2D<half4> texDeferNormal;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texPostBlur_write;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float depth = ap.depth[globalPos];
    if (depth <= 0.0) {
        texPostBlur_write[globalPos] = texBlur_read[globalPos];
        return;
    }

    float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);

    half4 normalData = texDeferNormal[globalPos];
    float3 normal = octohedral::decode(normalData.xy);
    float3 viewNormal = mul(float3x3(ap.camera.view), normal);

    float4 centerData = texAccumData_read[globalPos];
    float frameCount = centerData.b;
    float normHitDist = centerData.a;

    float radius = ReBLUR::computeBlurRadius(BlurRadiusPixels, frameCount, MaxAccumulatedFrames, normHitDist);
    float rotation = BlueNoise::sampleAnimated1D(globalPos, 3, ap.timing.frameCounter) * (2.0 * PI);

    float3 colorSum = texBlur_read[globalPos];
    float weightSum = 1.0;

    for (int i = 0; i < TapCount; i++) {
        float2 offset = ReBLUR::vogelDiscOffset(i, TapCount, rotation) * radius;
        int2 tapPos = int2(globalPos) + int2(round(offset));
        if (any(tapPos < 0) || any(tapPos >= int2(ap.game.renderSize))) continue;

        float tapDepth = ap.depth[tapPos];
        if (tapDepth <= 0.0) continue;

        float2 tapTexcoord = (tapPos + 0.5) / ap.game.renderSize;
        float3 tapClipPos = float3(tapTexcoord * 2.0 - 1.0, tapDepth);
        float3 tapViewPos = mul_project(ap.camera.projectionInv, tapClipPos);

        half4 tapNormalData = texDeferNormal[tapPos];
        float3 tapNormal = octohedral::decode(tapNormalData.xy);
        float3 tapViewNormal = mul(float3x3(ap.camera.view), tapNormal);

        float weight = ReBLUR::computeEdgeWeight(viewPos, viewNormal, tapViewPos, tapViewNormal);
        if (weight <= 1e-4) continue;

        colorSum += texBlur_read[tapPos] * weight;
        weightSum += weight;
    }

    texPostBlur_write[globalPos] = colorSum / max(weightSum, 1e-4);
}
