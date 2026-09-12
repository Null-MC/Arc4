public module sky_view;

import aperture;
import lib.common;
import lib.sky.shared;


namespace HillaireSky {

    internal Texture2D<half3> texSkyView;
    internal SamplerState skyViewSampler;

    public half3 sampleView(const in float2 texcoord) {
        return texSkyView.Sample(skyViewSampler, texcoord);
    }

    public half3 sampleView(const in PlanetAtmosphere planet, const in float3 skyPos, const in float3 rayDir, const in float3 sunDir) {
        return sampleView(toViewCoord(planet, skyPos, rayDir, sunDir));
    }

    public float2 toViewCoord(const in PlanetAtmosphere planet, const in float3 skyPos, const in float3 rayDir, const in float3 sunDir) {
        float height = length(skyPos);
        float3 up = skyPos / height;

        float elevation2 = max(pow2(height) - pow2(planet.RadiusGround_KM), 0.0);
        float horizonAngle = safeacos(sqrt(elevation2) / height);
        float altitudeAngle = horizonAngle - acos(dot(rayDir, up)); // Between -PI/2 and PI/2
        float azimuthAngle; // Between 0 and 2*PI
        if (abs(altitudeAngle) > (0.5*PI - 0.0001)) {
            // Looking nearly straight up or down.
            azimuthAngle = 0.0;
        } else {
            float3 right = cross(sunDir, up);
            float3 forward = cross(up, right);
            
            float3 projectedDir = normalize(rayDir - up*(dot(rayDir, up)));
            float sinTheta = dot(projectedDir, right);
            float cosTheta = dot(projectedDir, forward);
            azimuthAngle = atan2(sinTheta, cosTheta) + PI;
        }
        
        // Non-linear mapping of altitude angle. See Section 5.3 of the paper.
        float v = 0.5 + 0.5*sign(altitudeAngle) * sqrt(abs(altitudeAngle) * 2.0/PI);
        return float2(azimuthAngle / (2.0*PI), v);
    }
    
    void fromViewCoord(const in float2 texcoord, const in PlanetAtmosphere planet, const in float3 skyPos, out float3 rayDir, out float3 sunDir) {
        float azimuthAngle = (texcoord.x - 0.5) * 2.0*PI;

        // Non-linear mapping of altitude. See Section 5.3 of the paper.
        float adjV;
        if (texcoord.y < 0.5) {
            float coord = 1.0 - 2.0*texcoord.y;
            adjV = -coord*coord;
        } else {
            float coord = texcoord.y*2.0 - 1.0;
            adjV = coord*coord;
        }
        
        float height = length(skyPos);
        float3 upDir = skyPos / height;

        float elevation2 = max(pow2(height) - pow2(planet.RadiusGround_KM), 0.0);
        float horizonAngle = safeacos(sqrt(elevation2) / height) - 0.5*PI;
        float altitudeAngle = adjV*0.5*PI - horizonAngle;
        
        float cosAltitude = cos(altitudeAngle);
        rayDir = float3(cosAltitude*sin(azimuthAngle), sin(altitudeAngle), -cosAltitude*cos(azimuthAngle));
        
        float3 SunLocalDir = normalize(ap.celestial.sunPosition);
        float sunAltitude = (0.5*PI) - acos(dot(SunLocalDir, upDir));
        sunDir = float3(0.0, sin(sunAltitude), -cos(sunAltitude));
    }

}
