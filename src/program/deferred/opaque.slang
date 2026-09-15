import aperture;
import settings;
import lib.common;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.sun;
import lib.sky.moon;


[[vk::image_format("rgba16f")]]
RWTexture2D<half3> texMain_write;

Texture2D<half4> texDeferColor;
Texture2D<half4> texDeferSpecular;
Texture2D<half3> texDiffuse_read;
Texture2D<half3> texSpecular_read;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float depth = ap.depth[globalPos];
    half4 color;

    float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;

    if (userSettings.TAA_Enabled) {
        texcoord -= scene.TAA_jitter;
    }

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);

    if (depth > 0.0) {
        color = texDeferColor[globalPos];
        half3 albedo = pow(color.rgb, half3(2.2));

        if (userSettings.Debug_WhiteWorld) albedo = 1.0h;

        half3 diffuse = texDiffuse_read[globalPos];
        half4 specularMap = texDeferSpecular[globalPos];

        diffuse *= rcp(half3(PI));

        half emission = fract(specularMap.a);
        diffuse += emission * 1200.0h;

        color.rgb = albedo * diffuse * color.a;

        // TODO: add specular
        half3 specular = texSpecular_read[globalPos];
        float smoothness = pow2(specularMap.r);
        color.rgb += specular * smoothness;

        if (ap.camera.fluid == 1) {
            float viewDist = length(viewPos);
            color.rgb *= exp(-viewDist * WaterAbsorb);
        }
    }
    else {
        // sky
        float3 localPos = mul3(ap.camera.viewInv, viewPos);

        float3 sunDir = normalize(ap.celestial.sunPosition);

        float3 skyPos = planet.getSkyPosition(0.0);
        float3 localViewDir = normalize(localPos);
        color.rgb = 0.0h;

        if (planet.rayIntersectsGround(skyPos, localViewDir) <= 0.0) {
            float3 moonDir = normalize(ap.celestial.moonPosition);
            // half3 skyTransmit = planet.sampleTransmit(skyPos, localViewDir);

            float3 sunLight = renderSun(localViewDir, sunDir) * SunColor;
            // half3 sunTransmit = planet.sampleTransmit(skyPos, sunDir);
            color.rgb += half3(sunLight * 20.0);// * sunTransmit;

            float3 moonLight = renderMoon(localViewDir, moonDir) * MoonColor;
            // half3 moonTransmit = planet.sampleTransmit(skyPos, moonDir);
            color.rgb += half3(moonLight * 20.0);// * moonTransmit;
        }

        color.rgb *= planet.sampleTransmit(skyPos, localViewDir);
    }

    texMain_write[globalPos] = color.rgb;
}
