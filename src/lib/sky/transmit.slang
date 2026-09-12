public module sky_transmit;

import aperture;
import lib.common;
import lib.sky.shared;


namespace HillaireSky {

    internal Texture2D<half3> texSkyTransmit;
    internal SamplerState skyTransmitSampler;

    public half3 sampleTransmit(const in float2 texcoord) {
        return texSkyTransmit.Sample(skyTransmitSampler, texcoord);
    }

    public half3 sampleTransmit(const in PlanetAtmosphere planet, const in float3 pos, const in float3 sunDir) {
        return sampleTransmit(toTransmitCoord(planet, pos, sunDir));
    }
    
    public float2 toTransmitCoord(const in PlanetAtmosphere planet, const in float3 pos, const in float3 sunDir) {
        float world_y = length(pos);
        float3 up = pos / world_y;

        float2 texcoord;
        texcoord.x = dot(sunDir, up);
        texcoord.x = pow(abs(texcoord.x), (1.0/3.0)) * sign(texcoord.x);
        texcoord.x = texcoord.x * 0.5 + 0.5;

        texcoord.y = planet.getNormalizedHeight(world_y);
        return texcoord;
    }

    public void fromTransmitCoord(const in float2 texcoord, const in PlanetAtmosphere planet, out float3 pos, out float3 sunDir) {
        float sunCosTheta = 2.0*texcoord.x - 1.0;
        sunCosTheta = pow3(sunCosTheta);// * sign(sunCosTheta);

        float sunTheta = safeacos(sunCosTheta);
        float height_KM = planet.getWorldHeight(texcoord.y);
        
        pos = float3(0.0, height_KM, 0.0);
        sunDir = normalize(float3(0.0, sunCosTheta, -sin(sunTheta)));
    }

}

extension PlanetAtmosphere {
    half3 sampleTransmit(const in float3 skyPos, const in float3 sunDir) {
        return HillaireSky::sampleTransmit(this, skyPos, sunDir);
    }
}
