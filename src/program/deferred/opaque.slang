import aperture;
import settings;
import lib.common;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.sun;
import lib.sky.moon;


[[vk::image_format("rgba16f")]]
RWTexture2D<half3> texMain_write;

Texture2D<half4> texDiffuse_read;
Texture2D<half3> texOpaqueColor;
Texture2D<half4> texOpaqueSpecular;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float depth = ap.opaqueDepth[globalPos];
    half3 color;

    if (depth > 0.0) {
        half3 albedo;
        if (userSettings.Debug_WhiteWorld) albedo = 0.85h;
        else {
            color = texOpaqueColor[globalPos];
            albedo = pow(color, half3(2.2));
        }

        half3 diffuse = texDiffuse_read[globalPos].rgb;
        half4 specular = texOpaqueSpecular[globalPos];

        diffuse *= rcp(half3(PI));

        half emission = fract(specular.a);
        diffuse += emission * 1200.0h;

        color = albedo * diffuse;
    }
    else {
        float2 texcoord = (globalPos + 0.5) / ap.game.screenSize;

        if (userSettings.TAA_Enabled) {
            texcoord -= scene.TAA_jitter;
        }

        float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
        float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
        float3 localPos = mul3(ap.camera.viewInv, viewPos);

        float3 sunDir = normalize(ap.celestial.sunPosition);

        float3 skyPos = planet.getSkyPosition(0.0);
        float3 localViewDir = normalize(localPos);
        color = 0.0h;

        if (planet.rayIntersectsGround(skyPos, localViewDir) <= 0.0) {
            float3 moonDir = normalize(ap.celestial.moonPosition);

            float3 sunLight = renderSun(localViewDir, sunDir) * SunColor;
            half3 sunTransmit = planet.sampleTransmit(skyPos, sunDir);
            color += half3(sunLight * 20.0) * sunTransmit;

            float3 moonLight = renderMoon(localViewDir, moonDir) * MoonColor;
            half3 moonTransmit = planet.sampleTransmit(skyPos, moonDir);
            color += half3(moonLight * 20.0) * moonTransmit;
        }
    }

    texMain_write[globalPos] = color;
}
