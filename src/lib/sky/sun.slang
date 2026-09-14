public module sun;

import lib.common;

static const float sun_SizeRadians = 0.00931;
// static const float sun_distanceMm = 149600.0;
// static const float sun_radiusMm = 695.7;


// float solidAngle(float dist, float rad) {
//     return (2.0 * PI) * (1.0 - rad / (rad*rad + dist*dist));
// }

float skySphere(const in float3 rayDir, const in float3 lightDir, const in float solidAngle) {
    float minCosTheta = cos(solidAngle);
    float cosTheta = dot(rayDir, lightDir);
    return saturate((cosTheta - minCosTheta) / (1.0 - minCosTheta));
}

float renderSun(float3 rayDir, float3 sunDir) {
    return skySphere(rayDir, sunDir, sun_SizeRadians);
}
