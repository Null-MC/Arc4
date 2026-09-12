public module sun;

import lib.common;

// static const float sun_SizeRadians = 0.008901179;
// static const float sun_distanceMm = 149600.0;
// static const float sun_radiusMm = 695.7;


// float solidAngle(float dist, float rad) {
//     return (2.0 * PI) * (1.0 - rad / (rad*rad + dist*dist));
// }

// float skySphere(const in float3 rayDir, const in float3 lightDir, const in float solidAngle) {
//     float minCosTheta = cos(solidAngle);
//     float cosTheta = dot(rayDir, lightDir);
//     return saturate((cosTheta - minCosTheta) / (1.0 - minCosTheta));
// }

// float renderSun(float3 rayDir, float3 sunDir) {
//     // const float minCosTheta = cos(sunSolidAngle);
//     return skySphere(rayDir, sunDir, sun_SizeRadians);
// }

float renderSunWithBloom(float3 rayDir, float3 sunDir) {
    const float sunSolidAngle = 0.53 * PI/180.0;
    const float minCosTheta = cos(sunSolidAngle);

    float cosTheta = dot(rayDir, sunDir);
    if (cosTheta >= minCosTheta) return 1.0;
    
    float offset = minCosTheta - cosTheta;
    float gaussianBloom = exp(-offset*50000.0)*0.5;
    float invBloom = 1.0/(0.02 + offset*300.0)*0.01;
    return gaussianBloom + invBloom;
}
