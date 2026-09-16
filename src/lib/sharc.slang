public module sharc;

import aperture;

extern static const uint SHARC_BUCKET_COUNT;
static const uint SHARC_PROBE_COUNT = 4u;
static const uint SHARC_EMPTY_KEY = 0u;
static const uint SHARC_TOMBSTONE_KEY = 0xffffffffu;
static const float SHARC_CELL_SIZE = 1.0;
static const float SHARC_SURFACE_OFFSET = 0.01;
// Accumulation is 32-bit fixed point. Near-camera voxels receive many more
// samples than distant voxels, so leave headroom for dense Minecraft geometry.
static const float SHARC_RADIANCE_SCALE = 256.0;
static const float SHARC_MAX_ACCUMULATED_RADIANCE = 16384.0;
static const uint SHARC_MAX_FRAME_SAMPLES = 256u;
static const uint SHARC_MIN_QUERY_SAMPLES = 32u;
static const uint SHARC_MAX_HISTORY = 512u;
static const uint SHARC_STALE_FRAME_MAX = 120u;

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

uint2 sharcKey(const in int3 cell, const in float3 normal) {
    uint face = sharcFace(normal);
    uint3 mixedCell = asuint(cell) ^ (face * 0x9e3779b9u);
    uint keyX = sharcHash(mixedCell) | 1u;
    uint keyY = sharcHash(mixedCell.yzx + 0x85ebca6bu) | 1u;
    if (keyX == SHARC_TOMBSTONE_KEY) keyX = 0xfffffffdU;
    return uint2(keyX, keyY);
}

int3 sharcCell(const in float3 worldPos, const in float3 normal) {
    // Surface positions lie on block boundaries. Select the solid block side
    // consistently for both cache writes and reads.
    return int3(floor((worldPos - normal * SHARC_SURFACE_OFFSET) / SHARC_CELL_SIZE));
}

uint sharcIndex(const in uint key, const in uint probe) {
    uint step = ((key >> 16u) | 1u) * 2u + 1u;
    return (key + probe * step) & (SHARC_BUCKET_COUNT - 1u);
}

bool sharcNormalMatches(const in float3 cachedNormal, const in float3 normal) {
    return dot(cachedNormal, normal) >= 0.9;
}

uint sharcFind(const in uint2 key, const in float3 normal) {
    for (uint probe = 0u; probe < SHARC_PROBE_COUNT; probe++) {
        uint index = sharcIndex(key.x, probe);
        if (all(sharcHashEntries[index].key == key) &&
            sharcNormalMatches(sharcHashEntries[index].normalFrame.xyz, normal)) return index;
    }
    return SHARC_BUCKET_COUNT;
}

uint sharcAcquire(const in uint2 key, const in float3 normal) {
    uint tombstone = SHARC_BUCKET_COUNT;
    uint empty = SHARC_BUCKET_COUNT;

    for (uint probe = 0u; probe < SHARC_PROBE_COUNT; probe++) {
        uint index = sharcIndex(key.x, probe);
        uint currentKey = sharcHashEntries[index].key.x;

        if (currentKey == key.x && sharcHashEntries[index].key.y == key.y &&
            sharcNormalMatches(sharcHashEntries[index].normalFrame.xyz, normal)) {
            sharcHashEntries[index].normalFrame.w = ap.timing.frameCounter;
            return index;
        }

        if (currentKey == SHARC_TOMBSTONE_KEY && tombstone == SHARC_BUCKET_COUNT) {
            tombstone = index;
            continue;
        }

        if (currentKey == SHARC_EMPTY_KEY && empty == SHARC_BUCKET_COUNT) empty = index;
    }

    if (tombstone != SHARC_BUCKET_COUNT) {
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
            sharcHashEntries[tombstone].normalFrame = float4(normal, ap.timing.frameCounter);
            return tombstone;
        }
    }

    if (empty != SHARC_BUCKET_COUNT) {
        uint observed;
        InterlockedCompareExchange(
            sharcHashEntries[empty].key.x,
            SHARC_EMPTY_KEY,
            key.x,
            observed
        );
        if (observed == SHARC_EMPTY_KEY) {
            sharcHashEntries[empty].key.y = key.y;
            sharcHashEntries[empty].normalFrame = float4(normal, ap.timing.frameCounter);
            return empty;
        }
    }

    return SHARC_BUCKET_COUNT;
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

    uint2 key = sharcKey(sharcCell(worldPos, normal), normal);
    uint index = sharcAcquire(key, normal);
    if (index == SHARC_BUCKET_COUNT) return;
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
    uint2 key = sharcKey(sharcCell(worldPos, normal), normal);
    uint index = sharcFind(key, normal);
    if (index == SHARC_BUCKET_COUNT) {
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
    uint2 key = sharcKey(sharcCell(worldPos, normal), normal);
    uint occupied = 0u;
    SharcDebugSample result;
    result.occupancy = 0.0;
    result.collisions = 0.0;
    result.confidence = 0.0;
    result.radiance = 0.0;
    result.matched = false;

    for (uint probe = 0u; probe < SHARC_PROBE_COUNT; probe++) {
        uint index = sharcIndex(key.x, probe);
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
