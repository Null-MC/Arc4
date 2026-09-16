import aperture;
import settings;
import lib.common;
import lib.dda;
import lib.octohedral;
import lib.hemisphere;
import lib.shadows;
import lib.sharc;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;


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
    if (!userSettings.Sharc_Enabled) return;

    // Process a sparse, temporally distributed subset of primary pixels.
    uint sampleIndex = globalPos.x + globalPos.y * ap.game.renderSize.x;
    if ((sampleIndex + ap.timing.frameCounter * 17u) % 5u != 0u) return;

    float depth = ap.depth[globalPos];
    if (depth <= 0.0) return;

    float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
    if (userSettings.TAA_Enabled) texcoord -= scene.TAA_jitter;

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    half4 normalData = texDeferNormal[globalPos];
    float3 geoNormal = octohedral::decode(normalData.xy);
    float3 normal = octohedral::decode(normalData.zw);

    float3 rayOrigin = localPos + 0.04 * geoNormal;
    float3 worldPos = localPos + ap.camera.position;

    sharcAccumulate(worldPos, geoNormal, directLighting(localPos, normal), 1.0);

    float2 noise = BlueNoise::sampleAnimated2D(globalPos, 2, ap.timing.frameCounter);
    float3 rayDir = transform_to_world(normal, sampleCosineWeightedHemisphere(noise));
    float3 hitNormal;
    float traceDist = DDA::trace(hitNormal, rayOrigin, rayDir, userSettings.MaxTraceSteps);

    if (traceDist < 0.0) {
        float3 skyPos = planet.getSkyPosition(localPos);
        float3 sky = planet.sampleView(skyPos, rayDir, normalize(ap.celestial.sunPosition));
        sharcAccumulate(worldPos, geoNormal, PI * transformer.fromLinear(sky), 1.0);
        return;
    }

    float3 hitLocalPos = rayOrigin + rayDir * traceDist;
    float3 hitRadiance = directLighting(hitLocalPos, hitNormal);
    sharcAccumulate(hitLocalPos + ap.camera.position, hitNormal, hitRadiance, 1.0);
}
