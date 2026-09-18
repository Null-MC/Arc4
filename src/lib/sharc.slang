public module sharc;

import aperture;
import settings;

extern static const int SHARC_BUCKET_COUNT;
// Java only exports signed spec constants; alias to uint for use throughout this file.
static const uint SHARC_BUCKET_COUNT_U = uint(SHARC_BUCKET_COUNT);
static const uint SHARC_CASCADE_COUNT = 4u;
static const uint SHARC_BUCKETS_PER_CASCADE = SHARC_BUCKET_COUNT_U / SHARC_CASCADE_COUNT;
static const uint SHARC_PROBE_COUNT = 4u;
static const uint SHARC_EMPTY_KEY = 0u;
static const uint SHARC_TOMBSTONE_KEY = 0xffffffffu;
static const float SHARC_CASCADE_DISTANCE_0 = 16.0;
static const float SHARC_CASCADE_DISTANCE_1 = 64.0;
static const float SHARC_CASCADE_DISTANCE_2 = 256.0;
static const float SHARC_SURFACE_OFFSET = 0.01;
// Accumulation is 32-bit fixed point. Near-camera voxels receive many more
// samples than distant voxels, so leave headroom for dense Minecraft geometry.
static const float SHARC_RADIANCE_SCALE = 256.0;
static const float SHARC_MAX_ACCUMULATED_RADIANCE = 16384.0;
static const uint SHARC_MAX_FRAME_SAMPLES = 256u;
static const uint SHARC_MIN_QUERY_SAMPLES = 8u;
static const uint SHARC_MAX_HISTORY = 512u;
static const uint SHARC_STALE_FRAME_MAX = 120u;
// When all probes for a key are occupied by unrelated entries, force-evict
// whichever one has gone longest untouched rather than waiting for the
// passive stale sweep in Resolve. The minimum age avoids evicting entries
// that are still being actively refreshed by contending live cells.
static const float SHARC_FORCE_EVICT_MIN_AGE = 8.0;
// New entries are seeded from a neighboring cascade at reduced confidence
// instead of starting cold, to hide LOD transitions during camera movement.
static const float SHARC_SEED_SAMPLES = float(SHARC_MIN_QUERY_SAMPLES) * 0.5;

struct SharcHashEntry {
    uint2 key;
    float4 normalFrame;
};

struct SharcAccumulationEntry {
    uint radianceR;
    uint radianceG;
    uint radianceB;
    uint samples;
};

struct SharcResolvedEntry {
    float3 radiance;
    float samples;
};

RWStructuredBuffer<SharcHashEntry> sharcHashEntries;
RWStructuredBuffer<SharcAccumulationEntry> sharcAccumulation;
RWStructuredBuffer<SharcResolvedEntry> sharcResolved;

uint sharcHash(uint3 cell) {
    cell = cell * 1664525u + 1013904223u;
    uint hash = cell.x ^ (cell.y * 2246822519u) ^ (cell.z * 3266489917u);
    hash ^= hash >> 16u;
    hash *= 2246822519u;
    hash ^= hash >> 13u;
    return hash;
}

uint sharcFace(const in float3 normal) {
    float3 axis = abs(normal);
    if (axis.x >= axis.y && axis.x >= axis.z) return normal.x >= 0.0 ? 0u : 1u;
    if (axis.y >= axis.z) return normal.y >= 0.0 ? 2u : 3u;
    return normal.z >= 0.0 ? 4u : 5u;
}

uint sharcCascade(const in float3 worldPos) {
    float distanceToCamera = distance(worldPos, ap.camera.position);
    if (distanceToCamera < SHARC_CASCADE_DISTANCE_0) return 0u;
    if (distanceToCamera < SHARC_CASCADE_DISTANCE_1) return 1u;
    if (distanceToCamera < SHARC_CASCADE_DISTANCE_2) return 2u;
    return 3u;
}

float sharcCellSize(const in uint cascade) {
    return userSettings.Sharc_BucketSize * exp2(float(cascade));
}

float3 sharcCanonicalNormal(const in float3 normal) {
    uint face = sharcFace(normal);
    if (face == 0u) return float3(1.0, 0.0, 0.0);
    if (face == 1u) return float3(-1.0, 0.0, 0.0);
    if (face == 2u) return float3(0.0, 1.0, 0.0);
    if (face == 3u) return float3(0.0, -1.0, 0.0);
    if (face == 4u) return float3(0.0, 0.0, 1.0);
    return float3(0.0, 0.0, -1.0);
}

uint2 sharcKey(const in int3 cell, const in float3 normal, const in uint cascade) {
    uint face = sharcFace(normal);
    uint3 mixedCell = asuint(cell) ^ (face * 0x9e3779b9u) ^ (cascade * 0x85ebca6bu);
    uint keyX = sharcHash(mixedCell) | 1u;
    uint keyY = sharcHash(mixedCell.yzx + 0x85ebca6bu) | 1u;
    if (keyX == SHARC_TOMBSTONE_KEY) keyX = 0xfffffffdU;
    return uint2(keyX, keyY);
}

int3 sharcCell(const in float3 worldPos, const in float3 normal, const in uint cascade) {
    // Surface positions lie on block boundaries. Select the solid block side
    // consistently for both cache writes and reads.
    float3 canonicalNormal = sharcCanonicalNormal(normal);
    return int3(floor((worldPos - canonicalNormal * SHARC_SURFACE_OFFSET) / sharcCellSize(cascade)));
}

uint sharcIndex(const in uint key, const in uint probe, const in uint cascade) {
    uint step = ((key >> 16u) | 1u) * 2u + 1u;
    uint localIndex = (key + probe * step) & (SHARC_BUCKETS_PER_CASCADE - 1u);
    return cascade * SHARC_BUCKETS_PER_CASCADE + localIndex;
}

bool sharcNormalMatches(const in float3 cachedNormal, const in float3 normal) {
    return all(cachedNormal == sharcCanonicalNormal(normal));
}

uint sharcFind(const in uint2 key, const in float3 normal, const in uint cascade) {
    for (uint probe = 0u; probe < SHARC_PROBE_COUNT; probe++) {
        uint index = sharcIndex(key.x, probe, cascade);
        if (all(sharcHashEntries[index].key == key) &&
            sharcNormalMatches(sharcHashEntries[index].normalFrame.xyz, normal)) return index;
    }
    return SHARC_BUCKET_COUNT_U;
}

bool sharcFindInCascade(
    const in float3 worldPos,
    const in float3 normal,
    const in uint neighborCascade,
    out float3 radiance,
    out float samples
) {
    uint2 neighborKey = sharcKey(sharcCell(worldPos, normal, neighborCascade), normal, neighborCascade);
    uint neighborIndex = sharcFind(neighborKey, normal, neighborCascade);
    if (neighborIndex == SHARC_BUCKET_COUNT_U) {
        radiance = 0.0;
        samples = 0.0;
        return false;
    }

    SharcResolvedEntry entry = sharcResolved[neighborIndex];
    radiance = entry.radiance;
    samples = entry.samples;
    return samples > 0.0;
}

// Prefer the finer cascade's data first since it best matches surface detail.
void sharcSeedResolved(
    const in uint index,
    const in float3 worldPos,
    const in float3 normal,
    const in uint cascade
) {
    float3 radiance;
    float samples;

    if (cascade > 0u && sharcFindInCascade(worldPos, normal, cascade - 1u, radiance, samples)) {
        sharcResolved[index].radiance = radiance;
        sharcResolved[index].samples = min(samples, SHARC_SEED_SAMPLES);
        return;
    }

    if (cascade + 1u < SHARC_CASCADE_COUNT && sharcFindInCascade(worldPos, normal, cascade + 1u, radiance, samples)) {
        sharcResolved[index].radiance = radiance;
        sharcResolved[index].samples = min(samples, SHARC_SEED_SAMPLES);
    }
}

uint sharcAcquire(const in float3 worldPos, const in uint2 key, const in float3 normal, const in uint cascade) {
    float3 canonicalNormal = sharcCanonicalNormal(normal);
    uint tombstone = SHARC_BUCKET_COUNT_U;
    uint empty = SHARC_BUCKET_COUNT_U;
    uint victim = SHARC_BUCKET_COUNT_U;
    uint victimKey = 0u;
    float victimAge = SHARC_FORCE_EVICT_MIN_AGE;

    for (uint probe = 0u; probe < SHARC_PROBE_COUNT; probe++) {
        uint index = sharcIndex(key.x, probe, cascade);
        uint currentKey = sharcHashEntries[index].key.x;

        if (currentKey == key.x && sharcHashEntries[index].key.y == key.y &&
            sharcNormalMatches(sharcHashEntries[index].normalFrame.xyz, normal)) {
            sharcHashEntries[index].normalFrame.w = ap.timing.frameCounter;
            return index;
        }

        if (currentKey == SHARC_TOMBSTONE_KEY && tombstone == SHARC_BUCKET_COUNT_U) {
            tombstone = index;
            continue;
        }

        if (currentKey == SHARC_EMPTY_KEY && empty == SHARC_BUCKET_COUNT_U) {
            empty = index;
            continue;
        }

        float age = ap.timing.frameCounter - sharcHashEntries[index].normalFrame.w;
        if (age >= victimAge) {
            victimAge = age;
            victim = index;
            victimKey = currentKey;
        }
    }

    if (tombstone != SHARC_BUCKET_COUNT_U) {
        uint observed;
        InterlockedCompareExchange(
            sharcHashEntries[tombstone].key.x,
            SHARC_TOMBSTONE_KEY,
            key.x,
            observed
        );
        if (observed == SHARC_TOMBSTONE_KEY) {
            sharcAccumulation[tombstone].radianceR = 0u;
            sharcAccumulation[tombstone].radianceG = 0u;
            sharcAccumulation[tombstone].radianceB = 0u;
            sharcAccumulation[tombstone].samples = 0u;
            sharcResolved[tombstone].radiance = 0.0;
            sharcResolved[tombstone].samples = 0.0;
            sharcHashEntries[tombstone].key.y = key.y;
            sharcHashEntries[tombstone].normalFrame = float4(canonicalNormal, ap.timing.frameCounter);
            sharcSeedResolved(tombstone, worldPos, normal, cascade);
            return tombstone;
        }
    }

    if (empty != SHARC_BUCKET_COUNT_U) {
        uint observed;
        InterlockedCompareExchange(
            sharcHashEntries[empty].key.x,
            SHARC_EMPTY_KEY,
            key.x,
            observed
        );
        if (observed == SHARC_EMPTY_KEY) {
            sharcHashEntries[empty].key.y = key.y;
            sharcHashEntries[empty].normalFrame = float4(canonicalNormal, ap.timing.frameCounter);
            sharcSeedResolved(empty, worldPos, normal, cascade);
            return empty;
        }
    }

    if (victim != SHARC_BUCKET_COUNT_U) {
        uint observed;
        InterlockedCompareExchange(
            sharcHashEntries[victim].key.x,
            victimKey,
            key.x,
            observed
        );
        if (observed == victimKey) {
            sharcAccumulation[victim].radianceR = 0u;
            sharcAccumulation[victim].radianceG = 0u;
            sharcAccumulation[victim].radianceB = 0u;
            sharcAccumulation[victim].samples = 0u;
            sharcResolved[victim].radiance = 0.0;
            sharcResolved[victim].samples = 0.0;
            sharcHashEntries[victim].key.y = key.y;
            sharcHashEntries[victim].normalFrame = float4(canonicalNormal, ap.timing.frameCounter);
            sharcSeedResolved(victim, worldPos, normal, cascade);
            return victim;
        }
    }

    return SHARC_BUCKET_COUNT_U;
}

bool sharcReserveSample(const in uint index) {
    uint current = sharcAccumulation[index].samples;
    for (uint attempt = 0u; attempt < 8u; attempt++) {
        if (current >= SHARC_MAX_FRAME_SAMPLES) return false;

        uint observed;
        InterlockedCompareExchange(
            sharcAccumulation[index].samples,
            current,
            current + 1u,
            observed
        );
        if (observed == current) return true;
        current = observed;
    }
    return false;
}

void sharcAccumulate(
    const in float3 worldPos,
    const in float3 normal,
    const in float3 radiance,
    const in float weight
) {
    if (weight <= 0.0) return;

    uint cascade = sharcCascade(worldPos);
    uint2 key = sharcKey(sharcCell(worldPos, normal, cascade), normal, cascade);
    uint index = sharcAcquire(worldPos, key, normal, cascade);
    if (index == SHARC_BUCKET_COUNT_U) return;
    if (!sharcReserveSample(index)) return;

    uint3 value = uint3(
        min(max(radiance, 0.0), SHARC_MAX_ACCUMULATED_RADIANCE) *
        weight * SHARC_RADIANCE_SCALE
    );

    InterlockedAdd(sharcAccumulation[index].radianceR, value.x);
    InterlockedAdd(sharcAccumulation[index].radianceG, value.y);
    InterlockedAdd(sharcAccumulation[index].radianceB, value.z);
}

float3 sharcLookup(const in float3 worldPos, const in float3 normal, out float confidence) {
    uint cascade = sharcCascade(worldPos);
    uint2 key = sharcKey(sharcCell(worldPos, normal, cascade), normal, cascade);
    uint index = sharcFind(key, normal, cascade);
    if (index == SHARC_BUCKET_COUNT_U) {
        // No entry yet at this cascade (e.g. it just crossed an LOD boundary).
        // Borrow a neighboring cascade's data so queries don't go cold while
        // waiting for the sparse Update pass to revisit this exact cell.
        float3 neighborRadiance;
        float neighborSamples;
        if (cascade > 0u && sharcFindInCascade(worldPos, normal, cascade - 1u, neighborRadiance, neighborSamples)) {
            confidence = smoothstep(0.0, SHARC_SEED_SAMPLES, min(neighborSamples, SHARC_SEED_SAMPLES));
            return neighborRadiance;
        }
        if (cascade + 1u < SHARC_CASCADE_COUNT && sharcFindInCascade(worldPos, normal, cascade + 1u, neighborRadiance, neighborSamples)) {
            confidence = smoothstep(0.0, SHARC_SEED_SAMPLES, min(neighborSamples, SHARC_SEED_SAMPLES));
            return neighborRadiance;
        }

        confidence = 0.0;
        return 0.0;
    }

    SharcResolvedEntry entry = sharcResolved[index];
    float sampleCount = entry.samples;
    confidence = smoothstep(
        float(SHARC_MIN_QUERY_SAMPLES),
        float(SHARC_MAX_HISTORY),
        sampleCount
    );

    return entry.radiance;
}

struct SharcDebugSample {
    float occupancy;
    float collisions;
    float confidence;
    float3 radiance;
    bool matched;
};

SharcDebugSample sharcDebugSample(const in float3 worldPos, const in float3 normal) {
    uint cascade = sharcCascade(worldPos);
    uint2 key = sharcKey(sharcCell(worldPos, normal, cascade), normal, cascade);
    uint occupied = 0u;
    SharcDebugSample result;
    result.occupancy = 0.0;
    result.collisions = 0.0;
    result.confidence = 0.0;
    result.radiance = 0.0;
    result.matched = false;

    for (uint probe = 0u; probe < SHARC_PROBE_COUNT; probe++) {
        uint index = sharcIndex(key.x, probe, cascade);
        bool isOccupied = sharcHashEntries[index].key.x != SHARC_EMPTY_KEY &&
            sharcHashEntries[index].key.x != SHARC_TOMBSTONE_KEY;
        occupied += isOccupied ? 1u : 0u;
        if (all(sharcHashEntries[index].key == key) &&
            sharcNormalMatches(sharcHashEntries[index].normalFrame.xyz, normal)) {
            SharcResolvedEntry entry = sharcResolved[index];
            if (entry.samples > 0.0) {
                result.matched = true;
                result.radiance = entry.radiance;
                result.confidence = smoothstep(
                    float(SHARC_MIN_QUERY_SAMPLES),
                    float(SHARC_MAX_HISTORY),
                    entry.samples
                );
            }
        }
    }

    result.occupancy = result.matched ? 1.0 : 0.0;
    result.collisions = max(float(occupied) - (result.matched ? 1.0 : 0.0), 0.0) / float(SHARC_PROBE_COUNT);
    return result;
}
