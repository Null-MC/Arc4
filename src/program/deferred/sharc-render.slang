import aperture;
import settings;
import lib.common;
import lib.dda;
import lib.hemisphere;
import lib.octohedral;
import lib.shadows;
import lib.sharc;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;


[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texDiffuse_write;

Texture2D<half4> texDeferNormal;

float3 directLighting(const in float3 localPos, const in float3 normal) {
    float3 skyPos = planet.getSkyPosition(localPos);
    float3 sunDir = normalize(ap.celestial.sunPosition);
    float3 moonDir = normalize(ap.celestial.moonPosition);
    float3 result = planet.sampleTransmit(skyPos, sunDir) * SunColor * max(dot(normal, sunDir), 0.0);
    result += planet.sampleTransmit(skyPos, moonDir) * MoonColor * max(dot(normal, moonDir), 0.0);

    float3 shadowViewPos = mul3(ap.celestial.view, localPos);
    shadowViewPos.z += 0.02;
    if (let cascade = getShadowCascade(shadowViewPos)) {
        result *= ap.opaqueShadow.compare(cascade.position.xy, cascade.cascade, cascade.position.z);
    }
    return result;
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float depth = ap.depth[globalPos];
    float4 diffuse = 0.0;
    float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
    if (userSettings.TAA_Enabled) texcoord -= scene.TAA_jitter;

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    if (depth > 0.0) {
        diffuse.a = 1.0;
        half4 normalData = texDeferNormal[globalPos];
        float3 geoNormal = octohedral::decode(normalData.xy);
        float3 normal = octohedral::decode(normalData.zw);
        diffuse.rgb = directLighting(localPos, normal);

        float2 noise = BlueNoise::sampleAnimated2D(globalPos, 0, ap.timing.frameCounter);
        float3 rayDir = transform_to_world(normal, sampleCosineWeightedHemisphere(noise));
        float3 hitNormal;
        float traceDist = DDA::trace(hitNormal, localPos + 0.02 * geoNormal, rayDir, userSettings.MaxTraceSteps);

        if (traceDist < 0.0) {
            float3 skyPos = planet.getSkyPosition(localPos);
            float3 skyColor = planet.sampleView(skyPos, rayDir, normalize(ap.celestial.sunPosition));
            diffuse.rgb += PI * transformer.fromLinear(skyColor);
        }
        else {
            float3 hitLocalPos = localPos + rayDir * traceDist;
            hitLocalPos += 0.04 * geoNormal;

            float3 hitDiffuse = directLighting(hitLocalPos, hitNormal);
            float3 hitWorldPos = hitLocalPos + ap.camera.position;

            if (userSettings.SHARC_Enabled) {
                float confidence;
                float3 cachedRadiance = sharcLookup(hitWorldPos, hitNormal, confidence);
                // Keep a traced-lighting baseline while resolved SHARC history converges.
                float cacheWeight = confidence * 0.75;
                hitDiffuse = lerp(hitDiffuse, cachedRadiance, cacheWeight);
            }

            diffuse.rgb += fakeTexture(hitLocalPos) * hitDiffuse;
        }
    }

    diffuse.rgb = clamp(diffuse.rgb, 0.0, half.maxValue);
    texDiffuse_write[globalPos] = diffuse;
}
