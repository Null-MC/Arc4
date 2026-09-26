import aperture;
import settings;
import lib.common;
import lib.octohedral;
import lib.pbr.material;
import lib.sharc;


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

[[vk::image_format("rg16f")]]
RWTexture2D<float2> texNormalHistory_write;

[[vk::image_format("r32f")]]
RWTexture2D<float> texDepthHistory_write;

Texture2D<float4> texDiffuse_read;
Texture2D<float4> texSpecular_read;

Texture2D<half4> texDeferNormal;


int2 findClosestNeighbor(int2 uv, float searchDepth) {
    float searchDepthL = linearizeDepth(searchDepth, ap.camera.near, ap.camera.far);
    float maxDiff = 1.0;
    int2 offset = 0;

    for (int i = 0; i < 8; i++) {
        int2 sample_offset = sample_offsets[i] * 2;
        uint diffuseCounter = texDiffuseCounter_write[uv + sample_offset];
        if (diffuseCounter <= 1) continue;

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
    half4 normalData = texDeferNormal[globalPos];
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

    if (diffuseCounter == 0) {
        // diffuse = float3(1000,0,0);
        diffuse = 0.0;

        if (userSettings.Sharc_Enabled) {
            float3 geo_normal = octohedral::decode(normalData.xy);

            float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
            float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
            float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
            float3 localPos = mul3(ap.camera.viewInv, viewPos);

            float confidence;
            float3 worldPos = localPos + ap.camera.position;
            float3 cachedRadiance = sharcLookup(worldPos, geo_normal, confidence);
            // Keep a traced-lighting baseline while resolved SHARC history converges.
            float cacheWeight = confidence;// * 0.75;
            diffuse = lerp(diffuse, cachedRadiance, cacheWeight);
            diffuseCounter = 1;// int(confidence * 7.0) + 1;
        }
    }

    texDiffuse_write[globalPos] = diffuse;
    texDiffuseHistory_write[globalPos] = diffuse;
    texDiffuseCounter_write[globalPos] = ++diffuseCounter;

    texSpecular_write[globalPos] = specular;
    texSpecularHistory_write[globalPos] = specular;
    texSpecularCounter_write[globalPos] = ++specularCounter;

    texNormalHistory_write[globalPos] = normalData.xy;
    texDepthHistory_write[globalPos] = depth;
}
