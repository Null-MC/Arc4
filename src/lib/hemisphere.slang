public module hemisphere;

import lib.common;


float3 sampleCosineWeightedHemisphere(const in float2 u) {
    float r = sqrt(u.x);
    float theta = (2.0 * PI) * u.y;
    return float3(r * cos(theta), r * sin(theta), sqrt(max(0.0, 1.0 - u.x)));
}

float3 sampleSphere(const in float2 u) {
    float z = 1.0 - 2.0 * u.x;
    float r = sqrt(max(0.0, 1.0 - z * z));
    float phi = (2.0 * PI) * u.y;
    return float3(r * cos(phi), r * sin(phi), z);
}

float3 transform_to_world(const in float3 normal, const in float3 local_dir) {
    float3 up = abs(normal.z) < 0.999
        ? float3(0.0, 0.0, 1.0)
        : float3(1.0, 0.0, 0.0);
    
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);
    return normalize(tangent * local_dir.x + bitangent * local_dir.y + normal * local_dir.z);
}
