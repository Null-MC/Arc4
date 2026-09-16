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

        float3 albedo = pow(color.rgb, 2.2);

        float3 localViewDir = -normalize(localPos);
        float NoV = max(dot(tex_normal, localViewDir), 0.0);
        float F_s = F_schlick(NoV, f0, 1.0);
        bool is_reflect = F_s >= dither;

        float3 rayOrigin, rayViewDir;
        if (!is_reflect) {
            // refract
            float eta = ap.camera.fluid == 1
                ? (1.333 / 1.0)
                : (1.0 / 1.333);

            rayViewDir = refract(viewDir, viewNormal, eta);
            rayOrigin = localPos + 0.02 * geo_normal;

            if (all(rayViewDir == 0.0)) is_reflect = true;
        }

        if (is_reflect) {
            // Sample a visible GGX microfacet normal and reflect the incoming ray around it.
            float roughness = max(1.0 - specularMap.r, 0.001);
            float alpha = roughness * roughness;
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
            rayOrigin = localPos + 0.02 * geo_normal;
        }

        float3 rayDir = mul(float3x3(ap.camera.viewInv), rayViewDir);
        float3 sunDir = normalize(ap.celestial.sunPosition);

        float3 hit_localNormal;
        float traceDist = DDA::trace(hit_localNormal, rayOrigin, rayDir, userSettings.MaxTraceSteps);

        if (traceDist < 0.0) {
            // sky
            float3 skyPos = planet.getSkyPosition(localPos);

            specular.rgb = planet.sampleView(skyPos, rayDir, sunDir);
        }
        else {
            // hit
            float3 hit_localPos = localPos + rayDir * traceDist;
            float3 hit_skyPos = planet.getSkyPosition(hit_localPos);

            float3 sunLight = planet.sampleTransmit(hit_skyPos, sunDir);
            sunLight *= SunColor * max(dot(hit_localNormal, sunDir), 0.0);

            float3 moonDir = normalize(ap.celestial.moonPosition);
            float3 moonLight = planet.sampleTransmit(hit_skyPos, moonDir);
            moonLight *= MoonColor * max(dot(hit_localNormal, moonDir), 0.0);

            float3 hit_diffuse = sunLight + moonLight;

            float3 skyLightDir = normalize(ap.celestial.position);

            float3 shadow_normal;
            float shadow_traceDist = DDA::trace(shadow_normal, hit_localPos + 0.08 * hit_localNormal, skyLightDir, userSettings.MaxTraceSteps);

            if (shadow_traceDist >= 0.0) hit_diffuse = 0.0;
            else {
                // fallback to shadowmap
                float3 hit_shadowViewPos = mul3(ap.celestial.view, hit_localPos + 0.08 * hit_localNormal);
                hit_shadowViewPos.z += 0.02;
                
                if (let result = getShadowCascade(hit_shadowViewPos)) {
                    hit_diffuse *= ap.opaqueShadow.compare(result.position.xy, result.cascade, result.position.z);
                }
            }
            
            // fake albedo since no texture data
            float3 hit_albedo = fakeTexture(hit_localPos);

            specular.rgb = hit_albedo * hit_diffuse;
        }

        if (is_reflect) {
            int hcm = int(floor(f0 * 255.0 - 229.5));
            float metalness = step(0.9, f0);

            float3 F;
            if (hcm >= 0 && hcm < 8) {
                F = lazanyi_hcm[hcm].F(NoV);
            }
            else {
                float3 _f0 = lerp(min(f0, 0.9), albedo, metalness);
                F = LazanyiF(_f0, LazanyiF.f82_from_f0(_f0)).F(NoV);
            }

            float3 tint = lerp(1.0, albedo, metalness);
            specular.rgb *= F * tint;
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

    specular = clamp(specular, 0.0, 65000.0);

    texSpecular_write[globalPos] = specular;
}

float F_schlick(const in float cos_theta, const in float f0, const in float f90) {
    float invCosTheta = saturate(1.0 - cos_theta);
    return f0 + (f90 - f0) * pow5(invCosTheta);
}
