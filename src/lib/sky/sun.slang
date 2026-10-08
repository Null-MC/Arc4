public module sun;

import settings;
import lib.common;
import lib.sky.shared;


float skySphere(const in float3 rayDir, const in float3 lightDir, const in float solidAngle) {
    float minCosTheta = cos(solidAngle);
    float cosTheta = dot(rayDir, lightDir);
    return saturate((cosTheta - minCosTheta) / (1.0 - minCosTheta));
}

float renderSun(float3 rayDir, float3 sunDir) {
    return skySphere(rayDir, sunDir, planet.SunAngularRadius) * 20.0;
}



// static const float3 k_u1 = float3(0.40, 0.47, 0.55); 
// static const float3 k_u2 = float3(0.20, 0.23, 0.28);


// float3 renderSun(const in float3 rayDir, const in float3 sunDir) {
//     float cosTheta = dot(rayDir, sunDir);
//     float minCosTheta = cos(planet.SunAngularRadius);
//     if (cosTheta < minCosTheta) return 0.0;
    
//     float r2 = (1.0 - cosTheta) / (1.0 - minCosTheta);
//     float mu = sqrt(max(1.0 - r2, 0.0));
//     float term = 1.0 - mu;
    
//     float3 limbDarkening = 1.0 - (k_u1 * term) - (k_u2 * term * term);
    
//     return limbDarkening * 100.0;
// }
