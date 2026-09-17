import aperture;
import settings;
import rt_pipeline;
import lib.common;
import lib.octohedral;
import lib.hemisphere;
import lib.sharc;
import lib.shadow;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;


Texture2D<half4> texDeferNormal;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

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
    float3 geo_normal = octohedral::decode(normalData.xy);
    float3 tex_normal = octohedral::decode(normalData.zw);

    float3 rayOrigin = localPos + 0.04 * geo_normal;
    float3 worldPos = localPos + ap.camera.position;

    sharcAccumulate(worldPos, geo_normal, directLighting(localPos, geo_normal, tex_normal), 1.0);

    float2 noise = BlueNoise::sampleAnimated2D(globalPos, 2, ap.timing.frameCounter);
    float3 rayDir = transform_to_world(tex_normal, sampleCosineWeightedHemisphere(noise));

    var query = HWRT.startQuery(
        rayOrigin,
        rayDir,
        0.0,
        max(ap.world.renderDistance, 1.0),
        HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
        HWRT.RTFlags.NONE);
    
    float3 transmitColor = 1.0;
    while (query.proceed()) {
        let hit = query.getCandidate();
        if (hit.getHitType() == HWRT.HitType.TERRAIN && hit.getGeometryIndex() == HWRT.RTGeometryIndex.TRANSLUCENT) continue;
        
        let surface = HWRT.decodeHit(hit);
        float2 hit_uv = surface.getUV();
        float4 hit_color = surface.albedo().sampleLevel(hit_uv, 0.0) * surface.getColor();

        if (hit_color.a >= 0.99) query.acceptCandidate();
        else {
            float3 tint = transformer.fromGamma(hit_color.rgb);
            // tint = lerp(1.0, tint, hit_color.a);
            transmitColor *= tint * (1.0 - pow2(hit_color.a));
        }
    }

    if (!query.hasHit()) {
        float3 skyPos = planet.getSkyPosition(localPos);
        float3 sky = transmitColor * planet.sampleView(skyPos, rayDir, normalize(ap.celestial.sunPosition));
        sharcAccumulate(worldPos, geo_normal, PI * transformer.fromLinear(sky), 1.0);
        return;
    }

    var hit = query.getHit();
    var surface = HWRT.decodeHit(hit);
    float3 hit_localPos = surface.getPos();
    float3 hit_localNormal = surface.getNormal();

    float3 hitRadiance = directLighting(hit_localPos, hit_localNormal, hit_localNormal);

    float3 hit_albedo = surface.albedo().sampleLevel(surface.getUV(), 0.0).rgb * surface.getColor().rgb;
    hitRadiance *= transmitColor * transformer.fromGamma(hit_albedo.rgb);
    
    sharcAccumulate(hit_localPos + ap.camera.position, hit_localNormal, hitRadiance, 1.0);
}


float3 directLighting(const in float3 localPos, const in float3 geo_normal, const in float3 tex_normal) {
    float3 sunDir = normalize(ap.celestial.sunPosition);
    float3 moonDir = normalize(ap.celestial.moonPosition);
    float3 skyLightDir = normalize(ap.celestial.position);

    float3 skyPos = planet.getSkyPosition(localPos);
    float3 result = planet.sampleTransmit(skyPos, sunDir) * SunColor * max(dot(tex_normal, sunDir), 0.0);
    result += planet.sampleTransmit(skyPos, moonDir) * MoonColor * max(dot(tex_normal, moonDir), 0.0);

    return result * SampleShadow(localPos, geo_normal);
}
