public module light_sampling;

import aperture;
import rt_pipeline;
import lib.common;
import lib.noise.blue;
import lib.light.list;
import lib.light.data;
import lib.light.attenuation;
import lib.sky.shared;


static const uint LightRISCandidateCount = 8u;

struct VoxelLightSample {
    float3 lightWorldPos;
    float3 lightDir;
    float lightDist;
    float3 lightColor;
    float attenuation;
};


float3 sampleRandomVoxelLight(uint2 fragPos, float3 localPos, float3 geo_normal, float3 tex_normal) {
    float3 sectionPos = GlobalLights.getSectionPosition(localPos + 0.002 * geo_normal);
    int sectionIndex = GlobalLights.GetMapIndex(int3(floor(sectionPos)));
    if (sectionIndex < 0) return 0.0;

    VoxelLightRange range = LocalLightMap[sectionIndex];
    uint sampleCount = min(max(range.count, 0u), MaxLocalLightCount);
    if (sampleCount == 0u) return 0.0;

    float weightSum = 0.0;
    float selectedTarget = 0.0;
    VoxelLight selectedLight = LocalLightIndex[range.start];

    for (uint candidateIndex = 0u; candidateIndex < LightRISCandidateCount; candidateIndex++) {
        uint lightIndex = sampleLightIndex(fragPos, candidateIndex * 2u, sampleCount);
        VoxelLight light = LocalLightIndex[range.start + lightIndex];
        float target = estimateVoxelLightTarget(light, localPos, tex_normal);
        float weight = target * sampleCount;

        weightSum += weight;
        float replacement = min(BlueNoise::sampleAnimated1D(fragPos, int(candidateIndex * 2u + 1u), ap.timing.frameCounter), 0.99999994);
        if (weight > 0.0 && replacement * weightSum < weight) {
            selectedLight = light;
            selectedTarget = target;
        }
    }

    if (selectedTarget <= 0.0) return 0.0;

    float risWeight = weightSum / (float(LightRISCandidateCount) * selectedTarget);
    return sampleVoxelLight(selectedLight, localPos, geo_normal, tex_normal) * risWeight;
}

float3 sampleRandomFogLight(uint2 fragPos, float3 localPos) {
    float3 sectionPos = GlobalLights.getSectionPosition(localPos);
    int sectionIndex = GlobalLights.GetMapIndex(int3(floor(sectionPos)));
    if (sectionIndex < 0) return 0.0;

    VoxelLightRange range = LocalLightMap[sectionIndex];
    uint sampleCount = min(max(range.count, 0u), MaxLocalLightCount);
    if (sampleCount == 0u) return 0.0;

    float weightSum = 0.0;
    float selectedTarget = 0.0;
    VoxelLight selectedLight = LocalLightIndex[range.start];

    for (uint candidateIndex = 0u; candidateIndex < LightRISCandidateCount; candidateIndex++) {
        uint lightIndex = sampleLightIndex(fragPos, candidateIndex * 2u, sampleCount);
        VoxelLight light = LocalLightIndex[range.start + lightIndex];
        float target = estimateFogLightTarget(light, localPos);
        float weight = target * sampleCount;

        weightSum += weight;
        float replacement = min(BlueNoise::sampleAnimated1D(fragPos, int(candidateIndex * 2u + 1u), ap.timing.frameCounter), 0.99999994);
        if (weight > 0.0 && replacement * weightSum < weight) {
            selectedLight = light;
            selectedTarget = target;
        }
    }

    if (selectedTarget <= 0.0) return 0.0;

    float risWeight = weightSum / (float(LightRISCandidateCount) * selectedTarget);
    return sampleFogLight(selectedLight, localPos) * risWeight;
}

uint sampleLightIndex(const in uint2 fragPos, const in uint sampleIndex, const in uint sampleCount) {
    float r = BlueNoise::sampleAnimated1D(fragPos, int(sampleIndex), ap.timing.frameCounter);
    return min(uint(r * sampleCount), sampleCount - 1u);
}

VoxelLightSample getVoxelLightSample(const in VoxelLight light, const in float3 localPos) {
    VoxelLightSample sample;
    sample.lightWorldPos = light.voxelPos + 0.5;

    float3 worldPos = localPos + ap.camera.position;
    float3 fromLightWorld = worldPos - sample.lightWorldPos;
    sample.lightDist = length(fromLightWorld);
    sample.lightDir = fromLightWorld / sample.lightDist;

    half4 color_range = getLightColorRange(ap.blocks[light.blockId]);
    sample.lightColor = getColorSpace().fromGamma(color_range.rgb) * (color_range.a/16.0h) * BlockEmission;

    float att = Attenuation::getExponential(sample.lightDist);
    float attL = max(1.0 - sample.lightDist / color_range.a, 0.0);
    sample.attenuation = min(att, pow3(attL));
    return sample;
}

float estimateVoxelLightTarget(const in VoxelLight light, const in float3 localPos, const in float3 tex_normal) {
    VoxelLightSample sample = getVoxelLightSample(light, localPos);
    float lightF = (1.0/PI) * max(dot(tex_normal, -sample.lightDir), 0.0) * sample.attenuation;
    return luminance(sample.lightColor * lightF);
}

float estimateFogLightTarget(const in VoxelLight light, const in float3 localPos) {
    VoxelLightSample sample = getVoxelLightSample(light, localPos);
    return luminance(sample.lightColor * ((1.0/PI) * sample.attenuation));
}

float3 sampleVoxelLight(const in VoxelLight light, const in float3 localPos, const in float3 geo_normal, const in float3 tex_normal) {
    VoxelLightSample sample = getVoxelLightSample(light, localPos);

    float3 invDir = rcp(sample.lightDir + sign(sample.lightDir) * 1e-6);

    float3 t0 = -0.5 * invDir;
    float3 t1 =  0.5 * invDir;

    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);

    float tNear = maxOf(tmin);
    float tFar  = minOf(tmax);

    float3 lightShadow = 1.0;
    if (tNear <= tFar && tFar >= 0.0) {
        float tClosest = tFar + 0.002;
        sample.lightWorldPos += sample.lightDir * tClosest;

        float3 lightLocalPos = sample.lightWorldPos - ap.camera.position;

        float3 rayOrigin = localPos + 0.002 * geo_normal;
        float lightTraceDist = distance(rayOrigin, lightLocalPos);

        lightShadow = traceLight(rayOrigin, -sample.lightDir, lightTraceDist);
    }

    float lightF = (1.0/PI) * max(dot(tex_normal, -sample.lightDir), 0.0) * sample.attenuation;

    return sample.lightColor * lightShadow * lightF;
}

float3 sampleFogLight(const in VoxelLight light, const in float3 localPos) {
    VoxelLightSample sample = getVoxelLightSample(light, localPos);

    float3 invDir = rcp(sample.lightDir + sign(sample.lightDir) * 1e-6);

    float3 t0 = -0.5 * invDir;
    float3 t1 =  0.5 * invDir;

    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);

    float tNear = maxOf(tmin);
    float tFar  = minOf(tmax);

    float3 lightShadow = 1.0;
    if (tNear <= tFar && tFar >= 0.0) {
        float tClosest = tFar + 0.002;
        sample.lightWorldPos += sample.lightDir * tClosest;

        float3 lightLocalPos = sample.lightWorldPos - ap.camera.position;

        float3 rayOrigin = localPos;// + 0.002 * geo_normal;
        float lightTraceDist = distance(rayOrigin, lightLocalPos);

        lightShadow = traceLight(rayOrigin, -sample.lightDir, lightTraceDist);
    }

    float3 localDir = normalize(localPos);
    float VoL = dot(localDir, -sample.lightDir);
    float miePhase = getMiePhase(VoL);

    float lightF = sample.attenuation * miePhase;

    return sample.lightColor * lightShadow * lightF;
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
