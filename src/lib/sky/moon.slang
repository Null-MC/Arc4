public module moon;

import lib.common;

static const float moon_SizeRadians = 0.0098;


float skySphere(const in float3 rayDir, const in float3 lightDir, const in float solidAngle) {
    float minCosTheta = cos(solidAngle);
    float cosTheta = dot(rayDir, lightDir);
    return saturate((cosTheta - minCosTheta) / (1.0 - minCosTheta));
}

float renderMoon(float3 rayDir, float3 moonDir) {
    return skySphere(rayDir, moonDir, moon_SizeRadians);
}
