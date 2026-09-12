public module sky_multiscatter;

import aperture;
import lib.common;
import lib.sky.shared;


namespace HillaireSky {

    internal Texture2D<half3> texSkyMultiScatter;
    internal SamplerState skyMultiScatterSampler;


    public half3 sampleMultiScatter(const in float2 texcoord) {
        return texSkyMultiScatter.Sample(skyMultiScatterSampler, texcoord);
    }

    public half3 sampleMultiScatter(const in PlanetAtmosphere planet, const in float3 pos, const in float3 sunDir) {
        return sampleMultiScatter(toMultiScatterCoord(planet, pos, sunDir));
    }

    public float2 toMultiScatterCoord(const in PlanetAtmosphere planet, const in float3 pos, const in float3 sunDir) {
        float height = length(pos);
        float3 upDir = pos / height;

        float2 texcoord;
        texcoord.x = dot(sunDir, upDir) * 0.5 + 0.5;
        texcoord.y = planet.getNormalizedHeight(height);

        return texcoord;
    }

    public void fromMultiScatterCoord(const in float2 texcoord, const in PlanetAtmosphere planet, out float3 pos, out float3 sunDir) {
        float sunCosTheta = 2.0*texcoord.x - 1.0;
        float sunTheta = safeacos(sunCosTheta);
        float height = planet.getWorldHeight(texcoord.y);
        
        pos = float3(0.0, height, 0.0); 
        sunDir = normalize(float3(0.0, sunCosTheta, -sin(sunTheta)));
    }

}
