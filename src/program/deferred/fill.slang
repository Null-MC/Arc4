import aperture;
import settings;
import lib.common;
import lib.pbr.material;


[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuse_write;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuseHistory_write;

[[vk::image_format("r8ui")]]
RWTexture2D<uint> texDiffuseCounter_write;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texSpecular_write;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texSpecularHistory_write;

[[vk::image_format("r8ui")]]
RWTexture2D<uint> texSpecularCounter_write;

[[vk::image_format("r32f")]]
RWTexture2D<float> texDepthHistory_write;

Texture2D<float4> texDiffuse_read;
Texture2D<float4> texSpecular_read;


int2 findClosestNeighbor(int2 uv, float searchDepth) {
    float searchDepthL = linearizeDepth(searchDepth, ap.camera.near, ap.camera.far);
    float maxDiff = 0.2;
    int2 offset = 0;

    for (int i = 0; i < 8; i++) {
        int2 sample_offset = sample_offsets[i] * 2;
        // uint historyCounter = texHistoryCounter_write[uv + sample_offset];
        // if (historyCounter <= 1) continue;

        // float sampleDepth = texDepthHistory_read[uv + sample_offset];
        float sampleDepth = ap.depth[uv + sample_offset];
        float sampleDepthL = linearizeDepth(sampleDepth, ap.camera.near, ap.camera.far);
        float diff = abs(sampleDepthL - searchDepthL);

        if (diff < maxDiff) {
            offset = sample_offset;
            maxDiff = diff;
        }
    }

    return offset;
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

float linearizeDepth(float sampleDepth, float zNear, float zFar) {
    return (zNear * zFar) / (sampleDepth * (zFar - zNear) + zNear);
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    uint diffuseCounter = texDiffuseCounter_write[globalPos];
    uint specularCounter = texSpecularCounter_write[globalPos];
    float depth = ap.depth[globalPos];

    int2 uv_diffuse = globalPos;
    int2 uv_specular = globalPos;
    if (diffuseCounter == 0 || specularCounter == 0) {
        int2 uv_offset = findClosestNeighbor(globalPos, depth);

        if (diffuseCounter == 0) {
            uv_diffuse += uv_offset;
            diffuseCounter = texDiffuseCounter_write[uv_diffuse];
        }

        if (specularCounter == 0) {
            uv_specular += uv_offset;
            specularCounter = texSpecularCounter_write[uv_specular];
        }

        depth = ap.depth[globalPos + uv_offset];
    }

    float3 diffuse = texDiffuse_read[uv_diffuse].rgb;
    float3 specular = texSpecular_read[uv_specular].rgb;

    // if (historyCounter == 0) {
    //     diffuse = float3(1000,0,0);
    // }

    texDiffuse_write[globalPos] = diffuse;
    texDiffuseHistory_write[globalPos] = diffuse;
    texDiffuseCounter_write[globalPos] = ++diffuseCounter;

    texSpecular_write[globalPos] = specular;
    texSpecularHistory_write[globalPos] = specular;
    texSpecularCounter_write[globalPos] = ++specularCounter;

    texDepthHistory_write[globalPos] = depth;
}
