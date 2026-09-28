import aperture;
import settings;
import rt_pipeline;
import lib.common;
import lib.octohedral;


[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texDiffuse_write;

Texture2D<float4> texDiffuse_read;

Texture2D<half4> texDeferNormal;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float depth = ap.depth[globalPos];
    float4 diffuse = texDiffuse_read[globalPos];

    float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;

    if (userSettings.TAA_Enabled) {
        texcoord -= scene.TAA_jitter;
    }

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    if (depth > 0.0) {
        half4 normalData = texDeferNormal[globalPos];
        float3 geo_normal = octohedral::decode(normalData.xy);
        float3 tex_normal = octohedral::decode(normalData.zw);

        const float3 lightPos_main = float3(0.25, 0.1, -0.2);
        float3 hand_Light = 0.0;

        if (ap.game.mainHand > 0) {
            float3 lightPos = mul(float3x3(ap.camera.viewInv), lightPos_main);
            int block_emission = ap.blocks[ap.game.mainHand].emission;

            hand_Light += sampleLight(lightPos, localPos, geo_normal, tex_normal, block_emission);
        }

        if (ap.game.offHand > 0) {
            float3 lightPos = mul(float3x3(ap.camera.viewInv), -lightPos_main);
            int block_emission = ap.blocks[ap.game.offHand].emission;

            hand_Light += sampleLight(lightPos, localPos, geo_normal, tex_normal, block_emission);
        }


        diffuse.rgb += hand_Light / PI;
    }

    diffuse.rgb = clamp(diffuse.rgb, 0.0, half.maxValue);

    texDiffuse_write[globalPos] = diffuse;
}

float3 sampleLight(const in float3 lightPos, const in float3 localPos, const in float3 geo_normal, const in float3 tex_normal, const in int block_emission) {
    if (block_emission == 0) return 0.0;

    float3 lightDir = lightPos - localPos;
    float lightDist = length(lightDir);
    lightDir /= lightDist;

    float3 lightColor = getColorSpace().fromGamma(float3(1.0));
    float lightRange = (block_emission / 16.0) * BlockEmission;

    var query = HWRT.startQuery(
        localPos + 0.002 * geo_normal,
        lightDir,
        0.0,
        lightDist,
        HWRT.HitType.TERRAIN,
        HWRT.RTFlags.CULL_FRONT_FACES);

    float3 transmitColor = 1.0;
    while (query.proceed()) {
        let hit = query.getCandidate();
        let hitType = hit.getGeometryIndex();
        if (hitType == HWRT.RTGeometryIndex.SOLID) {
            query.acceptCandidate();
            continue;
        }

        let surface = HWRT.decodeHit(hit);
        float4 hit_color = surface.albedo().sampleLevel(surface.getUV(), 0.0) * surface.getColor();

        if (hitType == HWRT.RTGeometryIndex.CUTOUT) {
            if (hit_color.a >= 0.1) query.acceptCandidate();
            continue;
        }

        float3 hit_albedo = getColorSpace().fromGamma(hit_color.rgb);
        transmitColor *= getGlassTint(hit_albedo, hit_color.a);
    }

    float shadow = float(!query.hasHit());

    float lightF = max(dot(tex_normal, lightDir), 0.0);
    lightF *= shadow * lightRange * rcp(1.0 + pow2(lightDist));

    return lightF * lightColor * transmitColor;
}
