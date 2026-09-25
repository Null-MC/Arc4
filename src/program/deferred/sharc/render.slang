import aperture;
import settings;
import rt_pipeline;
import lib.common;
import lib.hemisphere;
import lib.octohedral;
import lib.sharc;
import lib.shadow;
import lib.pbr.material;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;


[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texDiffuse_write;

Texture2D<half4> texDeferNormal;
Texture2D<half4> texDeferSpecular;

Texture2D<half4> blockAtlasS;


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

    // Slightly scale down the view position to avoid precision issues.
    // viewPos *= 0.99;

    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float hitDistance = ap.world.renderDistance;

    if (depth > 0.0) {
        half4 normalData = texDeferNormal[globalPos];
        float3 geo_normal = octohedral::decode(normalData.xy);
        float3 tex_normal = octohedral::decode(normalData.zw);

        float3 skyLightDir = normalize(ap.celestial.position);
        float3 skyPos = planet.getSkyPosition(localPos);

        float3 sunDir = normalize(ap.celestial.sunPosition);
        float3 sunLight = planet.sampleTransmit(skyPos, sunDir);
        sunLight *= SunColor * max(dot(tex_normal, sunDir), 0.0);

        float3 moonDir = normalize(ap.celestial.moonPosition);
        float3 moonLight = planet.sampleTransmit(skyPos, moonDir);
        moonLight *= MoonColor * max(dot(tex_normal, moonDir), 0.0);

        float3 directLight = (sunLight + moonLight) / PI;

        diffuse.rgb = directLight * SampleShadowDisc(globalPos, localPos, geo_normal);

        half4 specularMap = texDeferSpecular[globalPos];
        float sss = getSpecularReader().sss(specularMap);

        const int SampleCount = 1;

        for (int i = 0; i < SampleCount; i++) {
            // sample index 2: index 0 is used by SampleShadowDisc, 1 by the SSS dither below.
            float2 noise = BlueNoise::sampleAnimated2D(globalPos, i+9, ap.timing.frameCounter);
            float3 rayDir = transform_to_world(tex_normal, sampleCosineWeightedHemisphere(noise));

            if (dot(rayDir, geo_normal) < 0.0) rayDir = -rayDir;
            
            float sssDither = BlueNoise::sampleAnimated1D(globalPos, i+27, ap.timing.frameCounter);
            bool is_sss = sss > sssDither;

            float3 rayBias = 0.002 * geo_normal;
            if (is_sss) {
                rayDir = -rayDir;
                rayBias = -rayBias;
            }

            var query = HWRT.startQuery(
                localPos + rayBias,
                rayDir,
                0.0,
                max(ap.world.renderDistance, 1.0),
                HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
                HWRT.RTFlags.USE_TWO_STATE_OMM);
            
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

            float3 sampleDiffuse;
            if (!query.hasHit()) {
                float3 skyPos = planet.getSkyPosition(localPos);
                float3 skyColor = planet.sampleView(skyPos, rayDir, normalize(ap.celestial.sunPosition));
                sampleDiffuse = getColorSpace().fromLinear(skyColor);
            }
            else {
                var hit = query.getHit();
                var surface = HWRT.decodeHit(hit);
                float3 hit_localPos = surface.getPos();
                float3 hit_localNormal = surface.getNormal();

                hitDistance = distance(localPos, hit_localPos);

                float3 hit_skyPos = planet.getSkyPosition(hit_localPos);
                float3 sunLight = planet.sampleTransmit(hit_skyPos, sunDir) * SunColor;
                float3 moonLight = planet.sampleTransmit(hit_skyPos, moonDir) * MoonColor;

                if (!is_sss) {
                    sunLight *= max(dot(hit_localNormal, sunDir), 0.0);
                    moonLight *= max(dot(hit_localNormal, moonDir), 0.0);
                }
                
                float3 hitDiffuse = (sunLight + moonLight) / PI;

                hitDiffuse *= SampleShadow(hit_localPos, hit_localNormal);

                float confidence;
                float3 hitWorldPos = hit_localPos + ap.camera.position;
                float3 cachedRadiance = sharcLookup(hitWorldPos, hit_localNormal, confidence);
                // Keep a traced-lighting baseline while resolved SHARC history converges.
                float cacheWeight = confidence * 0.75;
                hitDiffuse = lerp(hitDiffuse, cachedRadiance, cacheWeight);

                float2 hit_uv = surface.getUV();
                float3 hit_albedo = surface.albedo().sampleLevel(hit_uv, 0.0).rgb * surface.getColor().rgb;
                half4 hit_specular = blockAtlasS.SampleLevel(apt_nearestSampler, hit_uv, 0.0);
                hitDiffuse += mat_emission(hit_specular);
                
                sampleDiffuse = hitDiffuse * getColorSpace().fromGamma(hit_albedo);
            }

            diffuse.rgb += sampleDiffuse * transmitColor;
        }

        diffuse.rgb /= SampleCount;

        // diffuse.a = ReBLUR::normalizeHitDistance(hitDistance, length(viewPos));
    }

    diffuse.rgb = clamp(diffuse.rgb, 0.0, half.maxValue);
    texDiffuse_write[globalPos] = diffuse;
}
