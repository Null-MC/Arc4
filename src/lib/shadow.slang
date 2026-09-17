public module shadow;

import aperture;
import settings;
import rt_pipeline;
import lib.common;
import lib.noise.blue;
import lib.sky.sun;


float3 _SampleShadow(const in float3 localPos, const in float3 geo_normal, const in float3 skyLightDir) {
    float3 color = 1.0;

    var query = HWRT.startQuery(
        localPos + 0.002 * geo_normal,
        skyLightDir,
        0.0,
        max(ap.world.renderDistance, 1.0),
        HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
        HWRT.RTFlags.ACCEPT_FIRST_HIT_AND_END_SEARCH);
    
    while (query.proceed()) {
        let hit = query.getCandidate();
        if (hit.getHitType() == HWRT.HitType.TERRAIN && hit.getGeometryIndex() == HWRT.RTGeometryIndex.TRANSLUCENT) continue;
        
        var surface = HWRT.decodeHit(hit);
        float2 hit_uv = surface.getUV();
        let hit_color = surface.albedo().sampleLevel(hit_uv, 0.0) * surface.getColor();

        if (hit_color.a >= 0.99) query.acceptCandidate();
        else {
            float3 tint = transformer.fromGamma(hit_color.rgb);
            // tint = lerp(1.0, tint, hit_color.a);
            color *= tint * (1.0 - pow2(hit_color.a));
        }
    }

    if (query.hasHit()) return 0.0;
    return color;
}

float3 SampleShadow(const in float3 localPos, const in float3 geo_normal) {
    float3 skyLightDir = normalize(ap.celestial.position);
    return _SampleShadow(localPos, geo_normal, skyLightDir);
}

float3 SampleShadowDisc(const in int2 globalPos, const in float3 localPos, const in float3 geo_normal) {
    float3 skyLightDir = normalize(ap.celestial.position);

    float2 rayNoise = BlueNoise::sampleAnimated2D(globalPos, 0, ap.timing.frameCounter);
    float3 randomSunVec = getSampledSunDirection(skyLightDir, planet.SunAngularRadius, rayNoise);

    return _SampleShadow(localPos, geo_normal, randomSunVec);
}

void buildOrthonormalBasis(float3 v, out float3 b1, out float3 b2) {
    float sign = v.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (sign + v.z);
    float b = v.x * v.y * a;
    b1 = float3(1.0 + sign * v.x * v.x * a, sign * b, -sign * v.x);
    b2 = float3(b, sign + v.y * v.y * a, -v.y);
}

float3 getSampledSunDirection(float3 dir, float radius, float2 jitter) {
    float z = 1.0 - jitter.y * (1.0 - cos(radius));

    float sinTheta = sqrt(1.0 - z * z);
    float phi = 2.0 * PI * jitter.x;

    float3 localDir = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, z);

    float3 tan, biTan;
    buildOrthonormalBasis(dir, tan, biTan);

    return tan * localDir.x + biTan * localDir.y + dir * localDir.z;
}
