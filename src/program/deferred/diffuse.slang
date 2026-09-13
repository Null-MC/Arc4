import aperture;
import settings;
import lib.common;
import lib.dda;
import lib.octohedral;
import lib.shadows;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;


[[vk::image_format("rgba16f")]]
RWTexture2D<half4> texDiffuse_write;

Texture2D<half4> texOpaqueNormal;

float3 sampleCosineWeightedHemisphere(const in float2 u) {
    float r = sqrt(u.x);
    float theta = (2.0 * PI) * u.y;
    return float3(r * cos(theta), r * sin(theta), sqrt(max(0.0, 1.0 - u.x)));
}

float3 transform_to_world(const in float3 normal, const in float3 local_dir) {
    float3 up = abs(normal.z) < 0.999
        ? float3(0.0, 0.0, 1.0)
        : float3(1.0, 0.0, 0.0);

    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);

    // float3x3 TBN = float3x3(tangent, bitangent, normal);
    // return mul(local_dir, TBN);
    return normalize(
        tangent * local_dir.x +
        bitangent * local_dir.y +
        normal * local_dir.z
    );
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float depth = ap.opaqueDepth[globalPos];
    half4 diffuse = 0.0h;

    float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;

    if (userSettings.TAA_Enabled) {
        texcoord -= scene.TAA_jitter;
    }

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float3 sunDir = normalize(ap.celestial.sunPosition);

    if (depth > 0.0) {
        diffuse.a = 1.0h;

        half4 normalData = texOpaqueNormal[globalPos];
        float3 geo_normal = octohedral::decode(normalData.xy);
        float3 tex_normal = octohedral::decode(normalData.zw);

        float3 skyPos = planet.getSkyPosition(localPos);
        diffuse.rgb = planet.sampleTransmit(skyPos, sunDir);
        diffuse.rgb *= half3(rcp(PI) * SunColor * max(dot(tex_normal, sunDir), 0.0));

        float3 shadowViewPos = mul3(ap.celestial.view, localPos);
        shadowViewPos.z += 0.02;
        
        if (let result = getShadowCascade(shadowViewPos)) {
            diffuse.rgb *= half(ap.opaqueShadow.compare(result.position.xy, result.cascade, result.position.z));
        }

        // diffuse.rgb = 0.0h;

        float2 rayNoise = BlueNoise::sampleAnimated2D(globalPos, 0, ap.timing.frameCounter);
        float3 rayDir = sampleCosineWeightedHemisphere(rayNoise);
        rayDir = transform_to_world(tex_normal, rayDir);

        float traceDist = DDA::trace(localPos + 0.02 * geo_normal, rayDir, 32);
        if (traceDist < 0.0)
            diffuse.rgb += planet.sampleView(skyPos, rayDir, sunDir);
    }

    texDiffuse_write[globalPos] = diffuse;
}
