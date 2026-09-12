import aperture;
import settings;
import lib.scene;
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

Texture2D<half2> texOpaqueNormal;

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

    float3x3 TBN = float3x3(tangent, bitangent, normal);
    return mul(local_dir, TBN);
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

        float3 normal = octohedral::decode(texOpaqueNormal[globalPos]);

        float3 skyPos = HillaireSky::planet.getSkyPosition(localPos);
        diffuse.rgb = HillaireSky::planet.sampleTransmit(skyPos, sunDir);
        diffuse.rgb *= half3(rcp(PI) * SunColor * max(dot(normal, sunDir), 0.0));

        float3 shadowViewPos = mul3(ap.celestial.view, localPos);
        shadowViewPos.z += 0.02;
        
        if (let result = getShadowCascade(shadowViewPos)) {
            diffuse.rgb *= half(ap.opaqueShadow.compare(result.position.xy, result.cascade, result.position.z));
        }

        // float raySeed = InterleavedGradientNoiseTime(globalPos);
        float2 rayNoise = getAnimatedBlueNoise(globalPos, 0, ap.timing.frameCounter);
        float3 rayDir = sampleCosineWeightedHemisphere(rayNoise);
        rayDir = transform_to_world(normal, rayDir);

        float traceDist = DDA::trace(localPos + 0.02 * normal, rayDir, 32);
        if (traceDist < 0.0)
            diffuse.rgb += HillaireSky::sampleView(HillaireSky::planet, skyPos, rayDir, sunDir);
    }

    texDiffuse_write[globalPos] = diffuse;
}
