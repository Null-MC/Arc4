import aperture;
import settings;
import lib.scene;
import lib.common;
import lib.ign;
import lib.dda;
import lib.octohedral;
import lib.shadows;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;
import lib.sky.sun;
import lib.sky.moon;


[[vk::image_format("rgba16f")]]
RWTexture2D<half3> tex_write;

Texture2D<half3> texOpaqueColor;
Texture2D<half2> texOpaqueNormal;

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

    float3x3 TBN = float3x3(tangent, bitangent, normal);
    return mul(local_dir, TBN);
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.screenSize)) return;

    float depth = ap.opaqueDepth[globalPos];
    half3 color;

    float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;

    if (userSettings.TAA_Enabled) {
        texcoord -= scene.TAA_jitter;
    }

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float3 sunDir = normalize(ap.celestial.sunPosition);

    if (depth > 0.0) {
        color = texOpaqueColor[globalPos];
        float3 normal = octohedral::decode(texOpaqueNormal[globalPos]);

        float3 skyPos = HillaireSky::planet.getSkyPosition(localPos);
        float3 skyLight = HillaireSky::planet.sampleTransmit(skyPos, sunDir);
        skyLight *= SunColor * max(dot(normal, sunDir), 0.0);

        float3 shadowViewPos = mul3(ap.celestial.view, localPos);
        shadowViewPos.z += 0.02;
        
        if (let result = getShadowCascade(shadowViewPos)) {
            skyLight *= ap.opaqueShadow.compare(result.position.xy, result.cascade, result.position.z);
        }

        // float raySeed = InterleavedGradientNoiseTime(globalPos);
        float2 rayNoise = getAnimatedBlueNoise(globalPos, 0, ap.timing.frameCounter);
        float3 rayDir = sampleCosineWeightedHemisphere(rayNoise);
        rayDir = transform_to_world(normal, rayDir);

        float traceDist = DDA::trace(localPos + 0.02 * normal, rayDir, 32);
        if (traceDist < 0.0)
            skyLight += PI*HillaireSky::sampleView(HillaireSky::planet, skyPos, rayDir, sunDir);

        half3 albedo = pow(color, half3(2.2));
        color = half3(albedo/PI * skyLight);

        // color = (rayDir * 0.5 + 0.5) * 100.0;
    }
    else {
        float3 skyPos = HillaireSky::planet.getSkyPosition(0.0);
        float3 localViewDir = normalize(localPos);
        color = 0.0h;

        if (HillaireSky::planet.rayIntersectsGround(skyPos, localViewDir) <= 0.0) {
            float3 moonDir = normalize(ap.celestial.moonPosition);

            float3 sunLight = renderSunWithBloom(localViewDir, sunDir) * SunColor;
            half3 sunTransmit = HillaireSky::planet.sampleTransmit(skyPos, sunDir);
            color += half3(sunLight * 20.0) * sunTransmit;

            float3 moonLight = renderMoonWithBloom(localViewDir, moonDir) * MoonColor;
            half3 moonTransmit = HillaireSky::planet.sampleTransmit(skyPos, moonDir);
            color += half3(moonLight * 20.0) * moonTransmit;
        }
    }

    tex_write[globalPos] = color;
}
