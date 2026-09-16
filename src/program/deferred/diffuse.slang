import aperture;
import settings;
import lib.common;
import lib.dda;
import lib.octohedral;
import lib.shadows;
import lib.noise.ign;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;


[[vk::image_format("rgba16f")]]
RWTexture2D<half4> texDiffuse_write;

Texture2D<half4> texDeferNormal;

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

    return normalize(
        tangent * local_dir.x +
        bitangent * local_dir.y +
        normal * local_dir.z
    );
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float depth = ap.depth[globalPos];
    half4 diffuse = 0.0h;

    float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;

    if (userSettings.TAA_Enabled) {
        texcoord -= scene.TAA_jitter;
    }

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    if (depth > 0.0) {
        diffuse.a = 1.0h;

        half4 normalData = texDeferNormal[globalPos];
        float3 geo_normal = octohedral::decode(normalData.xy);
        float3 tex_normal = octohedral::decode(normalData.zw);

        float3 skyPos = planet.getSkyPosition(localPos);

        float3 sunDir = normalize(ap.celestial.sunPosition);
        float3 sunLight = planet.sampleTransmit(skyPos, sunDir);
        sunLight *= SunColor * max(dot(tex_normal, sunDir), 0.0);

        float3 moonDir = normalize(ap.celestial.moonPosition);
        float3 moonLight = planet.sampleTransmit(skyPos, moonDir);
        moonLight *= MoonColor * max(dot(tex_normal, moonDir), 0.0);

        diffuse.rgb = half3(sunLight + moonLight);

        float3 shadowViewPos = mul3(ap.celestial.view, localPos);
        shadowViewPos.z += 0.02;
        
        if (let result = getShadowCascade(shadowViewPos)) {
            diffuse.rgb *= half(ap.opaqueShadow.compare(result.position.xy, result.cascade, result.position.z));
        }

        // diffuse.rgb = 0.0h;

        float2 rayNoise = BlueNoise::sampleAnimated2D(globalPos, 0, ap.timing.frameCounter);
        float3 rayDir = sampleCosineWeightedHemisphere(rayNoise);
        rayDir = transform_to_world(tex_normal, rayDir);

        float3 hit_localNormal;
        float traceDist = DDA::trace(hit_localNormal, localPos + 0.02 * geo_normal, rayDir, userSettings.MaxTraceSteps);
        if (traceDist < 0.0) {
            // sky
            diffuse.rgb += PI * planet.sampleView(skyPos, rayDir, sunDir);
        }
        else {
            // hit
            float3 hit_localPos = localPos + rayDir * traceDist;
            float3 hit_skyPos = planet.getSkyPosition(hit_localPos);

            float3 sunLight = planet.sampleTransmit(hit_skyPos, sunDir);
            sunLight *= SunColor * max(dot(hit_localNormal, sunDir), 0.0);

            float3 moonLight = planet.sampleTransmit(hit_skyPos, moonDir);
            moonLight *= MoonColor * max(dot(hit_localNormal, moonDir), 0.0);

            float3 hit_diffuse = sunLight + moonLight;

            float3 skyLightDir = normalize(ap.celestial.position);

            float3 shadow_normal;
            float shadow_traceDist = DDA::trace(shadow_normal, hit_localPos + 0.02 * hit_localNormal, skyLightDir, userSettings.MaxTraceSteps);

            if (shadow_traceDist >= 0.0) hit_diffuse = 0.0;
            else {
                // fallback to shadowmap
                float3 hit_shadowViewPos = mul3(ap.celestial.view, hit_localPos);
                hit_shadowViewPos.z += 0.02;
                
                if (let result = getShadowCascade(hit_shadowViewPos)) {
                    hit_diffuse *= ap.opaqueShadow.compare(result.position.xy, result.cascade, result.position.z);
                }
            }

            // fake albedo since no texture data
            float3 hit_albedo = fakeTexture(hit_localPos);

            diffuse.rgb += hit_albedo * hit_diffuse;
        }
    }

    texDiffuse_write[globalPos] = diffuse;
}
