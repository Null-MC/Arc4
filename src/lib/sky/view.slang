public module sky_view;

import aperture;
import settings;
import lib.common;
import lib.sky.shared;
import lib.erp;
import lib.bicubic;


namespace HillaireSky {

    internal Texture2D<float4> texSkyView;
    internal Texture2D<float4> texSkyViewClouds;

    internal SamplerState skyViewSampler;


    public float3 sampleView(const in float2 texcoord) {
        return texSkyView.SampleBicubic(skyViewSampler, texcoord).rgb;
    }

    public float3 sampleViewClouds(const in float2 texcoord) {
        return texSkyViewClouds.SampleBicubic(skyViewSampler, texcoord).rgb;
    }

    public float3 sampleView(const in float3 rayDir) {
        return sampleView(toViewCoord(rayDir));
    }

    public float3 sampleViewClouds(const in float3 rayDir) {
        return sampleViewClouds(toViewCoord(rayDir));
    }

    // public half3 sampleView(const in PlanetBuffer planet, const in float3 skyPos, const in float3 rayDir, const in float3 sunDir) {
    //     return sampleView(toViewCoord(planet, skyPos, rayDir, sunDir));
    // }

    // public half3 sampleViewClouds(const in PlanetBuffer planet, const in float3 skyPos, const in float3 rayDir, const in float3 sunDir) {
    //     return sampleViewClouds(toViewCoord(planet, skyPos, rayDir, sunDir));
    // }

    public float2 toViewCoord(const in float3 rayDir) {
        return ERP::toUV(rayDir);
    }

    // public float2 toViewCoord(const in PlanetBuffer planet, const in float3 skyPos, const in float3 rayDir, const in float3 sunDir) {
    //     float height = length(skyPos);
    //     float3 up = skyPos / height;

    //     float elevation2 = max(pow2(height) - pow2(planet.RadiusGround_KM), 0.0);
    //     float horizonAngle = safeacos(sqrt(elevation2) / height);
    //     float altitudeAngle = horizonAngle - acos(dot(rayDir, up)); // Between -PI/2 and PI/2
    //     float azimuthAngle; // Between 0 and 2*PI
    //     if (abs(altitudeAngle) > (0.5*PI - 0.0001)) {
    //         // Looking nearly straight up or down.
    //         azimuthAngle = 0.0;
    //     } else {
    //         float3 right = cross(sunDir, up);
    //         float3 forward = cross(up, right);
            
    //         float3 projectedDir = normalize(rayDir - up*(dot(rayDir, up)));
    //         float sinTheta = dot(projectedDir, right);
    //         float cosTheta = dot(projectedDir, forward);
    //         azimuthAngle = atan2(sinTheta, cosTheta) + PI;
    //     }
        
    //     // Non-linear mapping of altitude angle. See Section 5.3 of the paper.
    //     float v = 0.5 + 0.5*sign(altitudeAngle) * sqrt(abs(altitudeAngle) * 2.0/PI);
    //     return float2(azimuthAngle / (2.0*PI), v);
    // }
    
    float3 fromViewCoord(const in float2 texcoord) {
        return ERP::fromUV(texcoord);
    }

    // void fromViewCoord(const in float2 texcoord, const in PlanetBuffer planet, const in float3 skyPos, out float3 rayDir, out float3 sunDir) {
    //     float azimuthAngle = (texcoord.x - 0.5) * 2.0*PI;

    //     // Non-linear mapping of altitude. See Section 5.3 of the paper.
    //     float adjV;
    //     if (texcoord.y < 0.5) {
    //         float coord = 1.0 - 2.0*texcoord.y;
    //         adjV = -coord*coord;
    //     } else {
    //         float coord = texcoord.y*2.0 - 1.0;
    //         adjV = coord*coord;
    //     }
        
    //     float height = length(skyPos);
    //     float3 upDir = skyPos / height;

    //     float elevation2 = max(pow2(height) - pow2(planet.RadiusGround_KM), 0.0);
    //     float horizonAngle = safeacos(sqrt(elevation2) / height) - 0.5*PI;
    //     float altitudeAngle = adjV*0.5*PI - horizonAngle;
        
    //     float cosAltitude = cos(altitudeAngle);
    //     // rayDir = float3(cosAltitude*sin(azimuthAngle), sin(altitudeAngle), -cosAltitude*cos(azimuthAngle));
    //     rayDir = float3(cosAltitude*cos(azimuthAngle), sin(altitudeAngle), cosAltitude*sin(azimuthAngle));
        
    //     float3 SunLocalDir = normalize(ap.celestial.sunPosition);
    //     float sunAltitude = (0.5*PI) - acos(dot(SunLocalDir, upDir));
    //     sunDir = float3(0.0, sin(sunAltitude), -cos(sunAltitude));
    // }

}

extension PlanetBuffer {
    float3 sampleView(const in float3 rayDir) {
        return HillaireSky::sampleView(rayDir);
    }

    float3 sampleViewClouds(const in float3 rayDir) {
        return HillaireSky::sampleViewClouds(rayDir);
    }

    // half3 sampleView(const in float3 skyPos, const in float3 rayDir, const in float3 sunDir) {
    //     return HillaireSky::sampleView(this, skyPos, rayDir, sunDir);
    // }

    // half3 sampleViewClouds(const in float3 skyPos, const in float3 rayDir, const in float3 sunDir) {
    //     return HillaireSky::sampleViewClouds(this, skyPos, rayDir, sunDir);
    // }
}
