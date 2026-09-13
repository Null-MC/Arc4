public module sky_multiscatter;

import aperture;
import settings;
import lib.common;
import lib.sky.shared;


namespace HillaireSky {

    internal Texture2D<half3> texSkyMultiScatter;
    internal SamplerState skyMultiScatterSampler;


    public half3 sampleMultiScatter(const in float2 texcoord) {
        return texSkyMultiScatter.Sample(skyMultiScatterSampler, texcoord);
    }

    public half3 sampleMultiScatter(const in PlanetBuffer planet, const in float3 skyPos, const in float3 sunDir) {
        return sampleMultiScatter(toMultiScatterCoord(planet, skyPos, sunDir));
    }

    public float2 toMultiScatterCoord(const in PlanetBuffer planet, const in float3 skyPos, const in float3 sunDir) {
        float height = length(skyPos);
        float3 upDir = skyPos / height;

        float2 texcoord;
        texcoord.x = dot(sunDir, upDir) * 0.5 + 0.5;
        texcoord.y = planet.getNormalizedHeight(height);

        return texcoord;
    }

    public void fromMultiScatterCoord(const in float2 texcoord, const in PlanetBuffer planet, out float3 skyPos, out float3 sunDir) {
        float sunCosTheta = 2.0*texcoord.x - 1.0;
        float sunTheta = safeacos(sunCosTheta);
        float height = planet.getWorldHeight(texcoord.y);
        
        skyPos = float3(0.0, height, 0.0); 
        sunDir = normalize(float3(0.0, sunCosTheta, -sin(sunTheta)));
    }

}

extension PlanetBuffer {
    half3 sampleMultiScatter(const in float3 skyPos, const in float3 sunDir) {
        return HillaireSky::sampleMultiScatter(this, skyPos, sunDir);
    }
}
