public module GGX;

import lib.common;


float ggxG1(const in float NoX, const in float alpha) {
    float alphaSquared = alpha * alpha;
    float denominator = NoX + sqrt(alphaSquared + (1.0 - alphaSquared) * NoX * NoX);
    return 2.0 * NoX / max(denominator, 1e-5);
}

float3 sampleGGXVNDF(
    const in float3 viewDir,
    const in float3 normal,
    const in float alpha,
    const in float2 random
) {
    float3 up = abs(normal.z) < 0.999
        ? float3(0.0, 0.0, 1.0)
        : float3(1.0, 0.0, 0.0);
    
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);

    float3 viewLocal = float3(
        dot(viewDir, tangent),
        dot(viewDir, bitangent),
        dot(viewDir, normal)
    );

    float3 stretchedView = normalize(float3(alpha * viewLocal.xy, viewLocal.z));

    float lengthSquared = dot(stretchedView.xy, stretchedView.xy);
    float3 stretchedTangent = lengthSquared > 0.0
        ? float3(-stretchedView.y, stretchedView.x, 0.0) / sqrt(lengthSquared)
        : float3(1.0, 0.0, 0.0);
    
    float3 stretchedBitangent = cross(stretchedView, stretchedTangent);

    float radius = sqrt(random.x);
    float phi = 2.0 * PI * random.y;
    float t1 = radius * cos(phi);
    float t2 = radius * sin(phi);
    float interpolation = 0.5 * (1.0 + stretchedView.z);
    t2 = lerp(sqrt(max(0.0, 1.0 - t1 * t1)), t2, interpolation);

    float3 stretchedNormal = t1 * stretchedTangent
        + t2 * stretchedBitangent
        + sqrt(max(0.0, 1.0 - t1 * t1 - t2 * t2)) * stretchedView;
    
    float3 microfacetLocal = normalize(float3(alpha * stretchedNormal.xy, max(0.0, stretchedNormal.z)));

    return normalize(
        tangent * microfacetLocal.x
        + bitangent * microfacetLocal.y
        + normal * microfacetLocal.z
    );
}
