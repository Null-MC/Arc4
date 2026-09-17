import aperture;
import settings;
import rt_pipeline;
import lib.common;
import lib.sharc;
import lib.shadow;
import lib.octohedral;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;
import lib.sky.sun;
import lib.pbr.lazanyi;
import lib.pbr.hcm;
import lib.pbr.ggx;


[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texSpecular_write;

Texture2D<half4> texDeferColor;
Texture2D<half4> texDeferNormal;
Texture2D<half4> texDeferSpecular;
Texture2D<uint> texDeferData;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float4 color = texDeferColor[globalPos];
    float depth = ap.depth[globalPos];
    float4 specular = 0.0;

    float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;

    if (userSettings.TAA_Enabled) {
        texcoord -= scene.TAA_jitter;
    }

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    if (depth > 0.0) {
        specular.a = 1.0;

        half4 normalData = texDeferNormal[globalPos];
        float3 geo_normal = octohedral::decode(normalData.xy);
        float3 tex_normal = octohedral::decode(normalData.zw);

        float3 viewDir = normalize(viewPos);
        float3 viewNormal = mul(float3x3(ap.camera.view), tex_normal);

        float dither = BlueNoise::sampleAnimated1D(globalPos, 0, ap.timing.frameCounter);

        half4 specularMap = texDeferSpecular[globalPos];

        float f0 = specularMap.g;
        if (f0 == 0.0) f0 = 0.04;

        float3 albedo = transformer.fromGamma(color.rgb);

        float3 localViewDir = -normalize(localPos);
        float NoV = max(dot(tex_normal, localViewDir), 0.0);
        float F_s = F_schlick(NoV, f0, 1.0);
        bool is_reflect = F_s >= dither;

        float3 rayViewDir;
        float roughness = max(1.0 - specularMap.r, 0.001);
        float alpha = roughness * roughness;
        if (!is_reflect) {
            // refract
            float eta = ap.camera.fluid == 1
                ? (1.333 / 1.0)
                : (1.0 / 1.333);

            rayViewDir = refract(viewDir, viewNormal, eta);

            if (all(rayViewDir == 0.0)) is_reflect = true;
        }

        if (is_reflect) {
            // Sample a visible GGX microfacet normal and reflect the incoming ray around it.
            float3 microfacetNormal = sampleGGXVNDF(
                -viewDir,
                viewNormal,
                alpha,
                BlueNoise::sampleAnimated2D(globalPos, 1, ap.timing.frameCounter)
            );

            rayViewDir = reflect(viewDir, microfacetNormal);
            if (dot(rayViewDir, viewNormal) <= 0.0) {
                rayViewDir = reflect(viewDir, viewNormal);
            }
        }

        float3 rayDir = mul(float3x3(ap.camera.viewInv), rayViewDir);
        float3 sunDir = normalize(ap.celestial.sunPosition);

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
            if (hit.getHitType() == HWRT.HitType.TERRAIN && hit.getGeometryIndex() == HWRT.RTGeometryIndex.TRANSLUCENT) continue;
            
            let surface = HWRT.decodeHit(hit);
            let hit_color = surface.albedo().sampleLevel(surface.getUV(), 0.0);// * surface.getColor();
            if (hit_color.a >= 0.99) query.acceptCandidate();
            else {
                float3 tint = transformer.fromGamma(hit_color.rgb);
                // tint = lerp(1.0, tint, hit_color.a);
                transmitColor *= tint * (1.0 - pow2(hit_color.a));
            }
        }

        float traceDist;
        if (!query.hasHit()) {
            // sky
            float3 skyPos = planet.getSkyPosition(localPos);

            float3 skyColor = planet.sampleView(skyPos, rayDir, sunDir);
            specular.rgb = transformer.fromLinear(skyColor);

            // specular.rgb += renderSun(rayDir, sunDir) * SunColor;
            traceDist = ap.camera.far;
        }
        else {
            // hit
            var hit = query.getHit();
            var surface = HWRT.decodeHit(hit);
            float3 hit_localPos = surface.getPos();
            float3 hit_localNormal = surface.getNormal();

            traceDist = distance(localPos, hit_localPos);

            float3 hit_skyPos = planet.getSkyPosition(hit_localPos);

            float3 sunLight = planet.sampleTransmit(hit_skyPos, sunDir);
            sunLight *= SunColor * max(dot(hit_localNormal, sunDir), 0.0);

            float3 moonDir = normalize(ap.celestial.moonPosition);
            float3 moonLight = planet.sampleTransmit(hit_skyPos, moonDir);
            moonLight *= MoonColor * max(dot(hit_localNormal, moonDir), 0.0);

            float3 hit_diffuse = sunLight + moonLight;
            hit_diffuse *= SampleShadow(hit_localPos, hit_localNormal);

            if (userSettings.Sharc_Enabled) {
                float sharcConfidence;
                float3 sharcRadiance = sharcLookup(
                    hit_localPos + ap.camera.position,
                    hit_localNormal,
                    sharcConfidence
                );

                // SHARC stores diffuse irradiance, so use it as a stable replacement
                // for the direct hit lighting instead of adding it a second time.
                float sharcWeight = sharcConfidence * 0.75;
                hit_diffuse = lerp(hit_diffuse, sharcRadiance, sharcWeight);
            }

            float3 hit_albedo = surface.albedo().sampleLevel(surface.getUV(), 0.0).rgb * surface.getColor().rgb;
            specular.rgb = hit_diffuse * transformer.fromGamma(hit_albedo);
        }

        specular.rgb *= transmitColor;

        if (is_reflect) {
            int hcm = int(floor(f0 * 255.0 - 229.5));
            float metalness = step(0.9, f0);

            float3 halfDir = normalize(localViewDir + sunDir);
            float VoH = max(dot(localViewDir, halfDir), 0.0);

            float3 F_NoV, F_VoH;
            var L = (hcm >= 0 && hcm < 8)
                ? lazanyi_hcm[hcm]
                : LazanyiF(lerp(f0, albedo, metalness));

            F_NoV = L.F(NoV);
            F_VoH = L.F(VoH);
            
            specular.rgb *= F_NoV;

            specular.rgb += sampleDirectSun(
                localPos,
                geo_normal,
                tex_normal,
                localViewDir,
                sunDir,
                alpha,
                // f0,
                F_VoH,
                // albedo,
                // metalness
            ) * SunColor;

            // albedo tinting
            specular.rgb *= lerp(1.0, albedo, metalness);
        }
        else {
            uint blockId = texDeferData[globalPos];
            if (blockId == 1) {
                // water
                if (traceDist > 0.0 && ap.camera.fluid == 0) {
                    specular.rgb *= exp(-traceDist * WaterAbsorb);
                }
            }
            else {
                // everything else
                specular.rgb *= albedo;
            }

            specular.rgb *= 1.0 - color.a;
        }
    }

    specular = clamp(specular, 0.0, half.maxValue);

    texSpecular_write[globalPos] = specular;
}

float F_schlick(const in float cos_theta, const in float f0, const in float f90) {
    float invCosTheta = saturate(1.0 - cos_theta);
    return f0 + (f90 - f0) * pow5(invCosTheta);
}

float3 sampleDirectSun(
    const in float3 localPos,
    const in float3 geo_normal,
    const in float3 tex_normal,
    const in float3 viewDir,
    const in float3 sunDir,
    const in float alpha,
    // const in float f0,
    const in float3 F_VoH,
    // const in float metalness
) {
    float NoV = max(dot(tex_normal, viewDir), 0.0);
    float NoL = max(dot(tex_normal, sunDir), 0.0);
    if (NoV <= 0.0 || NoL <= 0.0) return 0.0;

    float3 halfDir = normalize(viewDir + sunDir);
    float NoH = max(dot(tex_normal, halfDir), 0.0);
    // float VoH = max(dot(viewDir, halfDir), 0.0);

    float alphaSquared = alpha * alpha;
    float denominator = NoH * NoH * (alphaSquared - 1.0) + 1.0;
    float D = alphaSquared / max(PI * denominator * denominator, 1e-5);
    float G = ggxG1(NoV, alpha) * ggxG1(NoL, alpha);

    // float3 f0Color = lerp(f0, albedo, metalness);
    // float3 F = f0Color + (1.0 - f0Color) * pow5(1.0 - VoH);
    float3 brdf = F_VoH * D * G / max(4.0 * NoV * NoL, 1e-5);

    float3 shadow = SampleShadow(localPos, geo_normal);
    // if (shadow == 0.0) return 0.0;

    const float sunHalfAngle = 0.00931;
    const float sunSolidAngle = PI * sunHalfAngle * sunHalfAngle;
    float3 skyPos = planet.getSkyPosition(localPos);
    float3 sunRadiance = SunColor * planet.sampleTransmit(skyPos, sunDir);

    return sunRadiance * brdf * NoL * sunSolidAngle * shadow;
}
