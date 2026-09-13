import aperture;
import object_shader;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;
import lib.sky.sun;
import lib.sky.moon;

static const PlanetAtmosphere planet = planetEarth;


struct VertexData {
    float3 localPos;
};

struct FragmentData {
    half3 color : SV_Target0;
};

struct SkyShader : Shader<VertexData, FragmentData> {
    static void emitVertex(Vertex input, ObjectTransforms transforms, out VertexData output, out float4 clipPos) {
        output.localPos = input.pos().xyz;

        float4 viewPos = mul(transforms.view, input.pos());
        clipPos = mul(transforms.projection, viewPos);
    }

    static FragmentData shadeSurface(PixelData objectData, VertexData input) {
        float3 localViewDir = normalize(input.localPos);

        float3 skyPos = planet.getSkyPosition(0.0);
        float3 sunDir = normalize(ap.celestial.sunPosition);

        FragmentData output;
        output.color = sampleSkyView(planet, skyPos, localViewDir, sunDir);

        if (planet.rayIntersectsGround(skyPos, localViewDir) <= 0.0) {
            float3 sunLight = renderSunWithBloom(localViewDir, sunDir) * SunColor;
            half3 sunTransmit = sampleSkyTransmit(planet, skyPos, sunDir);
            output.color.rgb += half3(sunLight * 20.0) * sunTransmit;

            float3 moonDir = normalize(ap.celestial.moonPosition);

            float3 moonLight = renderMoonWithBloom(localViewDir, moonDir) * MoonColor;
            half3 moonTransmit = sampleSkyTransmit(planet, skyPos, moonDir);
            output.color.rgb += half3(moonLight * 20.0) * moonTransmit;
        }

        return output;
    }
}
