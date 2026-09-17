import aperture;
import settings;
import rt_pipeline;
import lib.common;
import lib.hemisphere;
import lib.octohedral;
import lib.sharc;
import lib.shadow;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;


[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texDiffuse_write;

Texture2D<half4> texDeferNormal;


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
        float3 geo_normal = octohedral::decode(normalData.xy);
        float3 tex_normal = octohedral::decode(normalData.zw);

        float3 sunDir = normalize(ap.celestial.sunPosition);
        float3 moonDir = normalize(ap.celestial.moonPosition);
        float3 skyLightDir = normalize(ap.celestial.position);

        float3 skyPos = planet.getSkyPosition(localPos);
        float3 directLight = planet.sampleTransmit(skyPos, sunDir) * SunColor * max(dot(tex_normal, sunDir), 0.0);
        directLight += planet.sampleTransmit(skyPos, moonDir) * MoonColor * max(dot(tex_normal, moonDir), 0.0);

        diffuse.rgb = directLight * SampleShadowDisc(globalPos, localPos, geo_normal);

        // diffuse.rgb = directLighting(localPos, geo_normal, tex_normal);

        float2 noise = BlueNoise::sampleAnimated2D(globalPos, 0, ap.timing.frameCounter);
        float3 rayDir = transform_to_world(tex_normal, sampleCosineWeightedHemisphere(noise));

        var query = HWRT.startQuery(
            localPos,
            rayDir,
            0.002,
            max(ap.world.renderDistance, 1.0),
            HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
            HWRT.RTFlags.NONE);
        
        while (query.proceed()) {
            let hit = query.getCandidate();
            if (hit.getHitType() == HWRT.HitType.TERRAIN && hit.getGeometryIndex() == HWRT.RTGeometryIndex.TRANSLUCENT) continue;
            
            let surface = HWRT.decodeHit(hit);
            float alpha = surface.albedo().sampleLevel(surface.getUV(), 0.0).a;// * surface.getColor().a;
            if (alpha >= 0.1) query.acceptCandidate();
        }

        if (!query.hasHit()) {
            float3 skyPos = planet.getSkyPosition(localPos);
            float3 skyColor = planet.sampleView(skyPos, rayDir, normalize(ap.celestial.sunPosition));
            diffuse.rgb += PI * transformer.fromLinear(skyColor);
        }
        else {
            var hit = query.getHit();
            var surface = HWRT.decodeHit(hit);
            float3 hit_localPos = surface.getPos();
            float3 hit_localNormal = surface.getNormal();

            // float3 hitDiffuse = directLighting(hit_localPos, hit_localNormal, hit_localNormal);
            float3 sunDir = normalize(ap.celestial.sunPosition);
            float3 moonDir = normalize(ap.celestial.moonPosition);
            float3 skyLightDir = normalize(ap.celestial.position);

            float3 skyPos = planet.getSkyPosition(localPos);
            float3 hitDiffuse = planet.sampleTransmit(skyPos, sunDir) * SunColor * max(dot(tex_normal, sunDir), 0.0);
            hitDiffuse += planet.sampleTransmit(skyPos, moonDir) * MoonColor * max(dot(tex_normal, moonDir), 0.0);

            hitDiffuse *= SampleShadow(localPos, geo_normal);

            // float3 hit_albedo = surface.albedo().sampleLevel(surface.getUV(), 0.0).rgb * surface.getColor().rgb;
            // hitDiffuse *= transformer.fromGamma(hit_albedo);

            float3 hitWorldPos = hit_localPos + ap.camera.position;

            float confidence;
            float3 cachedRadiance = sharcLookup(hitWorldPos, hit_localNormal, confidence);
            // Keep a traced-lighting baseline while resolved SHARC history converges.
            float cacheWeight = confidence * 0.75;
            hitDiffuse = lerp(hitDiffuse, cachedRadiance, cacheWeight);

            float3 hit_albedo = surface.albedo().sampleLevel(surface.getUV(), 0.0).rgb * surface.getColor().rgb;
            diffuse.rgb += hitDiffuse * transformer.fromGamma(hit_albedo);
        }
    }

    diffuse.rgb = clamp(diffuse.rgb, 0.0, half.maxValue);
    texDiffuse_write[globalPos] = diffuse;
}


// float3 directLighting(const in float3 localPos, const in float3 geo_normal, const in float3 tex_normal) {
//     float3 sunDir = normalize(ap.celestial.sunPosition);
//     float3 moonDir = normalize(ap.celestial.moonPosition);
//     float3 skyLightDir = normalize(ap.celestial.position);

//     float3 skyPos = planet.getSkyPosition(localPos);
//     float3 result = planet.sampleTransmit(skyPos, sunDir) * SunColor * max(dot(tex_normal, sunDir), 0.0);
//     result += planet.sampleTransmit(skyPos, moonDir) * MoonColor * max(dot(tex_normal, moonDir), 0.0);

//     return result * SampleShadow(localPos, geo_normal);
// }
