public module sun;

import settings;
import lib.common;


// float solidAngle(float dist, float rad) {
//     return (2.0 * PI) * (1.0 - rad / (rad*rad + dist*dist));
// }

float skySphere(const in float3 rayDir, const in float3 lightDir, const in float solidAngle) {
    float minCosTheta = cos(solidAngle);
    float cosTheta = dot(rayDir, lightDir);
    return saturate((cosTheta - minCosTheta) / (1.0 - minCosTheta));
}

float renderSun(float3 rayDir, float3 sunDir) {
    return skySphere(rayDir, sunDir, planet.SunAngularRadius) * 20.0;
}
