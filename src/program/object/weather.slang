import aperture;
import settings;
import object_shader;
import lib.common;
import lib.shadow;
import lib.sky.shared;
import lib.sky.transmit;


struct VertexData {
    float4 color : COLOR;
    float2 uv : TEXCOORD;
    float3 pos;
}

struct FragmentData {
    float4 color;
}


struct WeatherShader : Shader<VertexData, FragmentData> {
    static void emitVertex(Vertex input, ObjectTransforms transforms, out VertexData output, out float4 clipPos) {
        output.uv = input.uv();
        output.pos = input.pos().xyz;
        output.color = input.color();

        float4 viewPos = mul(transforms.view, input.pos());
        clipPos = mul(transforms.projection, viewPos);
    }

    static FragmentData shadeSurface(PixelData objectData, VertexData input) {
        float4 color = input.color;

        if (let texAlbedo = objectData.albedo()) {
            color *= texAlbedo.sampleTexture(input.uv);
        }

        ap.discardCutout(color);

        float3 albedo = getColorSpace().fromGamma(color.rgb);

        float3 skyPos = planet.getSkyPosition(input.pos);

        float3 sunDir = normalize(ap.celestial.sunPosition);
        float3 sunLight = SunColor * planet.sampleTransmit(skyPos, sunDir);
        sunLight = getColorSpace().fromLinear(sunLight);

        float3 moonDir = normalize(ap.celestial.moonPosition);
        float3 moonLight = MoonColor * planet.sampleTransmit(skyPos, moonDir);
        moonLight = getColorSpace().fromLinear(moonLight);

        color.rgb = (sunLight + moonLight) / PI;
        color.rgb *= SampleShadowDisc(objectData.screenPos.xy, input.pos, 0.0);
        color.rgb *= albedo;

        FragmentData output;
        output.color = color;
        return output;
    }
}
