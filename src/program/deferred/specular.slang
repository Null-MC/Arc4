import aperture;
import settings;
import rt_pipeline;
import lib.common;
import lib.sharc;
import lib.shadow;
import lib.hemisphere;
import lib.octohedral;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;
import lib.sky.sun;
import lib.pbr.lazanyi;
import lib.pbr.hcm;
import lib.pbr.ggx;
import lib.pbr.material;
import lib.ray_cone;


static const int MaxRefractInterfaces = 1;

[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texSpecular_write;

Texture2D<half4> blockAtlasS;

Texture2D<half4> texDeferColor;
Texture2D<half4> texDeferNormal;
Texture2D<half4> texDeferSpecular;
Texture2D<uint2> texDeferData;


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

    // Slightly scale down the view position to avoid precision issues.
    viewPos *= 0.99;

    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    if (depth > 0.0) {
        specular.a = 1.0;

        half4 normalData = texDeferNormal[globalPos];
        float3 geo_normal = octohedral::decode(normalData.xy);
        float3 tex_normal = octohedral::decode(normalData.zw);

        float3 viewDir = normalize(viewPos);
        float3 viewNormal = mul(float3x3(ap.camera.view), tex_normal);

        half4 specularMap = texDeferSpecular[globalPos];

        float f0 = SpecularReader.f0(specularMap);
        float ior_current = f0_to_ior(f0);

        float3 albedo = transformer.fromGamma(color.rgb);

        float3 localViewDir = -normalize(localPos);
        float NoV = max(dot(tex_normal, localViewDir), 0.0);
        float F_s = F_schlick(NoV, f0, 1.0);

        float dither = BlueNoise::sampleAnimated1D(globalPos, 73, ap.timing.frameCounter);
        bool is_reflect = F_s >= dither;

        float3 rayViewDir;
        float roughness = SpecularReader.roughness(specularMap);
        float alpha = roughness * roughness;
        if (!is_reflect) {
            // refract

            if (color.a > 0.99) {
                texSpecular_write[globalPos] = 0.0;
                return;
            }
            
            // float ior_near = ap.camera.fluid == 1 ? 1.333 : 1.0;
            float ior_near = 1.0;
            float eta = ior_near / ior_current;

            rayViewDir = refract(viewDir, viewNormal, eta);

            if (all(rayViewDir == 0.0)) is_reflect = true;
        }

        if (is_reflect) {
            // Sample a visible GGX microfacet normal and reflect the incoming ray around it.
            float3 microfacetNormal = sampleGGXVNDF(
                -viewDir,
                viewNormal,
                alpha,
                BlueNoise::sampleAnimated2D(globalPos, 37, ap.timing.frameCounter)
            );

            rayViewDir = reflect(viewDir, microfacetNormal);

            float3 geoViewNormal = mul(float3x3(ap.camera.view), geo_normal);
            if (dot(rayViewDir, geoViewNormal) <= 0.0) {
                // TODO: terminate instead of geometry?
                // rayViewDir = reflect(viewDir, geoViewNormal);
                texSpecular_write[globalPos] = 0.0;
                return;
            }
        }

        uint2 deferData = texDeferData[globalPos];
        // float fWidth = asfloat(deferData.g);
        // var cone = RayCone.CreateFromGBuffer(fWidth);

        float3 rayDir = mul(float3x3(ap.camera.viewInv), rayViewDir);
        float3 sunDir = normalize(ap.celestial.sunPosition);

        // Needed to weight the VNDF-sampled reflection by the Smith masking-shadowing ratio.
        float NoL = max(dot(tex_normal, rayDir), 0.0);

        HWRT.RTQuery query;
        float3 transmitColor = 1.0;
        if (MaxRefractInterfaces <= 1) {
            // simple
            query = HWRT.startQuery(
                localPos + (is_reflect ? 0.002 : -0.002) * geo_normal,
                rayDir,
                0.002,
                max(ap.world.renderDistance, 1.0),
                HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
                HWRT.RTFlags.NONE);

            while (query.proceed()) {
                let hit = query.getCandidate();
                let hitType = hit.getGeometryIndex();
                if (hitType == HWRT.RTGeometryIndex.SOLID) {
                    query.acceptCandidate();
                    break;
                }

                let surface = HWRT.decodeHit(hit);
                float4 hit_color = surface.albedo().sampleLevel(surface.getUV(), 0.0);// * surface.getColor();

                if (hitType == HWRT.RTGeometryIndex.CUTOUT && hit_color.a > 0.1) {
                    query.acceptCandidate();
                    break;
                }

                // transmitColor *= transformer.fromGamma(hit_color.rgb);
            }

            // if (query.hasHit()) {
            //     let hit = query.getHit();
            //     var hit_surface = HWRT.decodeHit(hit);
            //     float3 hit_localPos = hit_surface.getPos();
            //     float hitDist = distance(localPos, hit_localPos);

            //     var tint_query = HWRT.startQuery(
            //         localPos,
            //         rayDir,
            //         0.002,
            //         hitDist,
            //         HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
            //         HWRT.RTFlags.NONE);

            //     transmitColor = 1.0;
            //     while (tint_query.proceed()) {
            //         let tint_hit = tint_query.getCandidate();
            //         let tint_hitType = tint_hit.getGeometryIndex();
            //         let tint_surface = HWRT.decodeHit(tint_hit);
            //         float4 hit_color = tint_surface.albedo().sampleLevel(tint_surface.getUV(), 0.0);// * surface.getColor();

            //         transmitColor *= transformer.fromGamma(hit_color.rgb);
            //     }
            // }
        }
        else {
            // complex
            bool is_air = false;

            query = HWRT.startQuery(
                localPos,// - 0.002 * geo_normal,
                rayDir,
                0.002,
                max(ap.world.renderDistance, 1.0),
                HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
                HWRT.RTFlags.NONE);
            
            transmitColor = 1.0;
            for (int i = 0; i < MaxRefractInterfaces; i++) {
                while (query.proceed()) {
                    let hit = query.getCandidate();
                    let surface = HWRT.decodeHit(hit);
                    float3 hit_localPos = surface.getPos();
                    
                    query.acceptCandidate();
                }
                
                if (!query.hasHit() || i == MaxRefractInterfaces - 1) break;
                
                let hit = query.getHit();
                if (hit.getGeometryIndex() != HWRT.RTGeometryIndex.TRANSLUCENT) break;

                // bright red if hit any translucent surface
                // texSpecular_write[globalPos] = float4(1000,0,0,1);
                // return;

                // TODO: ?
                let surface = HWRT.decodeHit(hit);
                float2 hit_uv = surface.getUV();
                let hit_color = surface.albedo().sampleLevel(hit_uv, 0.0) * surface.getColor();
                if (hit_color.a > 0.9) break;

                float3 tint = transformer.fromGamma(hit_color.rgb);
                // tint *= 1.0 - hit_color.a;
                tint = lerp(1.0, tint, hit_color.a);
                transmitColor *= tint;

                float3 hit_localPos = surface.getPos();
                float3 hit_localNormal = surface.getNormal();

                // TODO: re-refract
                half4 hit_specular = blockAtlasS.SampleLevel(apt_nearestSampler, hit_uv, 0.0);
                float hit_f0 = SpecularReader.f0(hit_specular);

                float hit_ior = is_air ? f0_to_ior(hit_f0) : 1.0;
                // float hit_eta = (is_air ? 1.0 : ior_current) / hit_ior;
                float hit_eta = ior_current / hit_ior;

                // if (dot(rayDir, hit_localNormal) < 0.0) hit_localNormal = -hit_localNormal;
                if (is_air) hit_localNormal = -hit_localNormal;

                rayDir = refract(rayDir, hit_localNormal, hit_eta);
                ior_current = hit_ior;
                is_air = !is_air;

                query = HWRT.startQuery(
                    hit_localPos,// + 0.002 * hit_localNormal,
                    rayDir,
                    0.002,
                    max(ap.world.renderDistance, 1.0),
                    HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
                    HWRT.RTFlags.NONE);
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

            float3 hit_diffuse = (sunLight + moonLight) / PI;
            hit_diffuse *= SampleShadow(hit_localPos, hit_localNormal);

            hit_diffuse += sampleIndirect(globalPos, hit_localPos, hit_localNormal);

            float2 hit_uv = surface.getUV();
            half4 hit_specular = blockAtlasS.SampleLevel(apt_nearestSampler, hit_uv, 0.0);

            float hit_smoothness = hit_specular.r;
            float hit_metalness = SpecularReader.metalness(hit_specular);
            hit_diffuse *= 1.0 - hit_metalness * sqrt(hit_smoothness);

            // let size = surface.albedo().getSize();
            // let cone2 = cone.Propagate(distance(localPos, hit_localPos));
            // var mip = cone2.CalculateMipLevel(size.z);

            float3 hit_albedo = surface.albedo().sampleLevel(hit_uv, 0.0).rgb * surface.getColor().rgb;
            hit_diffuse += mat_emission(hit_specular);

            specular.rgb = hit_diffuse * transformer.fromGamma(hit_albedo);
        }

        specular.rgb *= transmitColor;

        if (is_reflect) {
            int hcm = SpecularReader.hcm(specularMap);
            float metalness = SpecularReader.metalness(specularMap);

            float3 halfDir = normalize(localViewDir + sunDir);
            float VoH = max(dot(localViewDir, halfDir), 0.0);

            float3 F_NoV, F_VoH;
            var L = (hcm >= 0 && hcm < 8)
                ? lazanyi_hcm[hcm]
                : LazanyiF(lerp(f0, albedo, metalness));

            // is_reflect was already chosen with probability F_s, so dividing by it here
            // avoids re-applying Fresnel a second time on top of that selection frequency.
            F_NoV = L.F(NoV) / max(F_s, 1e-3);
            F_VoH = L.F(VoH) / max(F_s, 1e-3);

            // VNDF importance sampling requires this visibility ratio to conserve energy.
            float visibility = ggxG2OverG1(NoV, NoL, alpha);
            specular.rgb *= F_NoV * visibility;

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
            specular.rgb *= lerp(1.0, sqrt(albedo), metalness);

            // TODO: THis should not exist!
            float smoothness = specularMap.r;
            specular.rgb *= sqrt(smoothness);
        }
        else {
            uint blockId = deferData.r;
            if (blockId == 1) {
                // water
                if (traceDist > 0.0 && ap.camera.fluid == 0) {
                    specular.rgb *= exp(-traceDist * WaterAbsorb);
                }
            }
            else {
                // everything else
                specular.rgb *= lerp(1.0, albedo, color.a);
            }

            // specular.rgb *= 1.0 - color.a;
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

float3 sampleIndirect(const in int2 globalPos, const in float3 localPos, const in float3 localNormal) {
    float2 rayNoise = BlueNoise::sampleAnimated2D(globalPos, 0, ap.timing.frameCounter);
    float3 rayDir = sampleCosineWeightedHemisphere(rayNoise);
    rayDir = transform_to_world(localNormal, rayDir);
    
    var query = HWRT.startQuery(
        localPos + 0.002 * localNormal,
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
            break;
        }

        let surface = HWRT.decodeHit(hit);
        float4 hit_color = surface.albedo().sampleLevel(surface.getUV(), 0.0) * surface.getColor();

        if (hitType == HWRT.RTGeometryIndex.CUTOUT && hit_color.a >= 0.1) {
            query.acceptCandidate();
            break;
        }

        float3 tint = transformer.fromGamma(hit_color.rgb);
        tint *= 1.0 - hit_color.a;
        // tint = lerp(1.0, tint, hit_color.a);
        transmitColor *= tint;
    }

    float3 diffuse;
    if (!query.hasHit()) {
        // sky
        float3 skyPos = planet.getSkyPosition(localPos);
        float3 sunDir = normalize(ap.celestial.sunPosition);
        float3 skyColor = planet.sampleView(skyPos, rayDir, sunDir);
        diffuse = transformer.fromLinear(skyColor);
    }
    else {
        // hit
        var hit = query.getHit();
        var surface = HWRT.decodeHit(hit);
        float3 hit_localPos = surface.getPos();
        float3 hit_localNormal = surface.getNormal();

        // TODO
        diffuse = 0.0;
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
            diffuse = lerp(diffuse, sharcRadiance, sharcWeight);
        }
    }

    return diffuse * transmitColor;
}

float f0_to_ior(const in float f0) {
    // Convert reflectance at normal incidence (f0) to index of refraction (ior)
    float sqrt_f0 = sqrt(f0);
    return (1.0 + sqrt_f0) / (1.0 - sqrt_f0);
}
