public module light_sampling;

import aperture;
import rt_pipeline;
import lib.common;
import lib.noise.blue;
import lib.light.list;
import lib.light.data;
import lib.light.attenuation;


float3 sampleRandomVoxelLight(uint2 fragPos, float3 localPos, float3 geo_normal, float3 tex_normal) {
    float3 sectionPos = GlobalLights.getSectionPosition(localPos + 0.002 * geo_normal);
    int sectionIndex = GlobalLights.GetMapIndex(int3(floor(sectionPos)));
    if (sectionIndex < 0) return 0.0;

    VoxelLightRange range = LocalLightMap[sectionIndex];
    uint bin_count = clamp(range.count, 0u, MaxLocalLightCount);

    // Pick one random light and sample
    float r = BlueNoise::sampleAnimated1D(fragPos, 0, ap.timing.frameCounter);
    uint i = uint(r * bin_count);

    if (bin_count <= 0 || i >= MaxLocalLightCount) return 0.0;

    VoxelLight light = LocalLightIndex[range.start + i];
    return sampleVoxelLight(light, localPos, geo_normal, tex_normal) * bin_count;
}

float3 sampleVoxelLight(const in VoxelLight light, const in float3 localPos, const in float3 geo_normal, const in float3 tex_normal) {
    // VoxelLight light = GlobalLightIndex[range.start + i];
    float3 lightWorldPos = light.voxelPos + 0.5;

    // offset the light position towards sampling point within block bounds
    float3 worldPos = localPos + ap.camera.position;
    float3 fromLightWorld = worldPos - lightWorldPos;
    float lightDist = length(fromLightWorld);
    float3 lightDir = fromLightWorld / lightDist;

    float3 invDir = rcp(lightDir + sign(lightDir) * 1e-6);

    float3 t0 = -0.5 * invDir;
    float3 t1 =  0.5 * invDir;

    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);

    float tNear = maxOf(tmin);
    float tFar  = minOf(tmax);

    float3 lightShadow = 1.0;
    if (tNear <= tFar && tFar >= 0.0) {
        float tClosest = tFar + 0.002;
        lightWorldPos += lightDir * tClosest;

        float3 lightLocalPos = lightWorldPos - ap.camera.position;

        float3 rayOrigin = localPos + 0.002 * geo_normal;
        float lightTraceDist = distance(rayOrigin, lightLocalPos);

        lightShadow = traceLight(rayOrigin, -lightDir, lightTraceDist);
    }

    half4 color_range = getLightColorRange(ap.blocks[light.blockId]);
    float3 lightColor = getColorSpace().fromGamma(color_range.rgb) * (color_range.a/16.0h) * BlockEmission;

    float lightF = (1.0/PI) * max(dot(tex_normal, -lightDir), 0.0);
    float att = Attenuation::getExponential(lightDist);
    float attL = max(1.0 - lightDist / color_range.a, 0.0);
    lightF *= min(att, pow3(attL));
    // lightF *= Attenuation::getLinear(lightDist, color_range.a);

    return lightColor * lightShadow * lightF;
}

float3 traceLight(const in float3 rayOrigin, const in float3 rayDir, const float rayDist) {
    var query = HWRT.startQuery(
        rayOrigin,
        rayDir,
        0.0,
        min(rayDist, 16.0),
        HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
        HWRT.RTFlags.NONE);

    float3 transmitColor = 1.0;
    while (query.proceed()) {
        let hit = query.getCandidate();
        let hitType = hit.getGeometryIndex();

        if (hitType == HWRT.RTGeometryIndex.SOLID) {
            query.acceptCandidate();
            continue;
        }

        let surface = HWRT.decodeHit(hit);
        float4 hit_color = surface.albedo().sampleLevel(surface.getUV(), 0.0) * surface.getColor();

        if (hitType == HWRT.RTGeometryIndex.CUTOUT) {
            if (hit_color.a >= 0.1) query.acceptCandidate();
            continue;
        }

        float3 hit_albedo = getColorSpace().fromGamma(hit_color.rgb);
        transmitColor *= getGlassTint(hit_albedo, hit_color.a);
    }

    if (query.hasHit()) transmitColor = 0.0;

    return transmitColor;
}
