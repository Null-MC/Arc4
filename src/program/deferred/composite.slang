import aperture;
import settings;
import lib.common;
import lib.pbr.material;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;
import lib.sky.sun;
import lib.sky.moon;
import lib.octohedral;
import lib.sharc;


[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texMain_write;

Texture2D<half4> texDeferColor;
Texture2D<half4> texDeferNormal;
Texture2D<half4> texDeferSpecular;
Texture2D<half3> texDiffuse_read;
Texture2D<half4> texSpecular_read;

[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float depth = ap.depth[globalPos];
    float4 color;

    float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;

    if (userSettings.TAA_Enabled) {
        texcoord -= scene.TAA_jitter;
    }

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);

    if (depth > 0.0) {
        color = texDeferColor[globalPos];
        float3 albedo = getColorSpace().fromGamma(color.rgb);

        if (userSettings.Debug_WhiteWorld) albedo = 1.0;

        float3 diffuseLight = texDiffuse_read[globalPos];
        half4 specularMap = texDeferSpecular[globalPos];

        float f0 = getSpecularReader().f0(specularMap);
        float metalness = getSpecularReader().metalness(specularMap);

        float smoothness = specularMap.r;
        diffuseLight *= 1.0 - metalness * sqrt(smoothness);

        diffuseLight += mat_emission(specularMap);

        color.rgb = albedo * diffuseLight * color.a;

        if (userSettings.SpecularEnabled) {
            float4 specularLight = texSpecular_read[globalPos];
            color.rgb *= 1.0 - specularLight.a;
            color.rgb += specularLight.rgb;// * smoothness;
        }

        if (ap.camera.fluid == 1) {
            float viewDist = length(viewPos);
            color.rgb *= exp(-viewDist * WaterAbsorb);
        }

        if (userSettings.Debug_SHARC && userSettings.Sharc_Enabled) {
            float3 geo_normal = octohedral::decode(texDeferNormal[globalPos].xy);
            float3 localPos = mul3(ap.camera.viewInv, viewPos);

            float3 worldPos = localPos + ap.camera.position;
            SharcDebugSample sample = sharcDebugSample(worldPos, geo_normal);
            float3 occupancyColor = lerp(
                float3(0.01, 0.01, 0.02),
                float3(0.08, 0.8, 0.16),
                sample.occupancy
            );
            occupancyColor = lerp(occupancyColor, float3(1.0, 0.12, 0.02), sample.collisions);

            if (sample.matched) {
                float confidence = sample.confidence;
                float3 radianceColor = max(sample.radiance, 0.05);
                color.rgb = lerp(occupancyColor, radianceColor, 0.7);
                color.rgb *= lerp(0.35, 1.5, confidence);
            }
            else {
                color.rgb = occupancyColor;
            }
        }
    }
    else {
        // sky
        float3 localPos = mul3(ap.camera.viewInv, viewPos);

        float3 skyPos = planet.getSkyPosition(0.0);
        float3 localViewDir = normalize(localPos);
        color.rgb = 0.0h;

        float3 sunDir = normalize(ap.celestial.sunPosition);

        if (planet.rayIntersectsGround(skyPos, localViewDir) <= 0.0) {
            float3 sunLight = renderSun(localViewDir, sunDir) * SunColor;

            float3 moonDir = normalize(ap.celestial.moonPosition);
            float3 moonLight = renderMoon(localViewDir, moonDir) * MoonColor;

            color.rgb = sunLight + moonLight;

            float3 transmit = planet.sampleTransmit(skyPos, localViewDir);
            color.rgb *= getColorSpace().fromLinear(transmit);
        }

        if (!userSettings.VolumetricEnabled) {
            float3 skyColor = planet.sampleView(skyPos, localViewDir, sunDir);
            color.rgb += getColorSpace().fromLinear(skyColor);
        }
    }

    color.rgb = clamp(color.rgb, 0.0, half.maxValue);

    texMain_write[globalPos] = color.rgb;
}
