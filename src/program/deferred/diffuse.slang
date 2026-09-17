import aperture;
import settings;
import rt_pipeline;
import lib.common;
import lib.shadow;
import lib.hemisphere;
import lib.octohedral;
import lib.noise.ign;
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

    if (userSettings.TAA_Enabled) {
        texcoord -= scene.TAA_jitter;
    }

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    if (depth > 0.0) {
        diffuse.a = 1.0;

        half4 normalData = texDeferNormal[globalPos];
        float3 geo_normal = octohedral::decode(normalData.xy);
        float3 tex_normal = octohedral::decode(normalData.zw);

        // localPos += 0.002 * geo_normal;

        float3 skyPos = planet.getSkyPosition(localPos);

        float3 sunDir = normalize(ap.celestial.sunPosition);
        float3 sunLight = planet.sampleTransmit(skyPos, sunDir);
        sunLight *= SunColor * max(dot(tex_normal, sunDir), 0.0);

        float3 moonDir = normalize(ap.celestial.moonPosition);
        float3 moonLight = planet.sampleTransmit(skyPos, moonDir);
        moonLight *= MoonColor * max(dot(tex_normal, moonDir), 0.0);

        diffuse.rgb = half3(sunLight + moonLight);

        diffuse.rgb *= SampleShadowDisc(globalPos, localPos, geo_normal);

        // diffuse.rgb = 0.0h;

        float2 rayNoise = BlueNoise::sampleAnimated2D(globalPos, 0, ap.timing.frameCounter);
        float3 rayDir = sampleCosineWeightedHemisphere(rayNoise);
        rayDir = transform_to_world(tex_normal, rayDir);

        var query = HWRT.startQuery(
            localPos,
            rayDir,
            0.002,
            max(ap.world.renderDistance, 1.0),
            HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
            HWRT.RTFlags.NONE);
        
        float3 transmitColor = 1.0;
        while (query.proceed()) {
            let hit = query.getCandidate();            
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
            // sky
            float3 skyColor = planet.sampleView(skyPos, rayDir, sunDir);
            diffuse.rgb += PI * transmitColor * transformer.fromLinear(skyColor);
        }
        else {
            // hit
            var hit = query.getHit();
            var surface = HWRT.decodeHit(hit);
            float3 hit_localPos = surface.getPos();
            float3 hit_localNormal = surface.getNormal();

            float3 hit_skyPos = planet.getSkyPosition(hit_localPos);

            float3 sunLight = planet.sampleTransmit(hit_skyPos, sunDir);
            sunLight *= SunColor * max(dot(hit_localNormal, sunDir), 0.0);

            float3 moonLight = planet.sampleTransmit(hit_skyPos, moonDir);
            moonLight *= MoonColor * max(dot(hit_localNormal, moonDir), 0.0);

            float3 hit_diffuse = sunLight + moonLight;
            hit_diffuse *= SampleShadow(hit_localPos, hit_localNormal);

            float3 hit_albedo = surface.albedo().sampleLevel(surface.getUV(), 0.0).rgb * surface.getColor().rgb;
            diffuse.rgb += hit_diffuse * transmitColor * transformer.fromGamma(hit_albedo);
        }
    }

    texDiffuse_write[globalPos] = diffuse;
}
