import aperture;
import lib.common;
import lib.noise.blue;
import lib.light.data;
import lib.light.list;


static const int GroupSize = 8*4*8;

groupshared VoxelLight shared_lights[MaxLocalLightCount];
groupshared Atomic<uint> shared_counter;
groupshared uint global_start;

struct ComputeInput {
    uint3 globalPos : SV_DispatchThreadID;
    uint localIndex : SV_GroupIndex;
    uint3 localPos : SV_GroupThreadID;
    uint3 groupPos : SV_GroupID;
};


[[shader("compute")]]
[numthreads(8,4,8)]
void main(ComputeInput input) {
    int map_index = GlobalLights.GetMapIndex(input.groupPos);
    if (map_index < 0 || map_index >= LightList_MaxIndexCount) return;

    if (input.localIndex == 0u) {
        shared_counter.store(0u);
    }

    GroupMemoryBarrierWithGroupSync();

    buildLocalReservoir(input.localIndex, input.groupPos, map_index);

    GroupMemoryBarrierWithGroupSync();

    uint total_count = shared_counter.load();
    uint stored_count = min(total_count, MaxLocalLightCount);

    if (input.localIndex == 0u) {
        global_start = LightListCounters[0].local.add(stored_count);
    }

    GroupMemoryBarrierWithGroupSync();

    LocalLightMap[map_index] = VoxelLightRange(global_start, total_count);
    copyReservoirToLocalList(input.localIndex, stored_count);
}

// All threads cooperate: each bin's lights are strided across the group, and the
// atomic counter hands out a unique candidate index to every accepted light.
void buildLocalReservoir(const in uint localIndex, const in uint3 groupPos, const in int mapIndex) {
    // Lights inside this bin always reach it
    scanBin(localIndex, groupPos, GlobalLightMap[mapIndex], false, 0);

    int3 worldOffset = int3(floor(ap.camera.position / 8.0)) - LightList_SectionSize/2;

    for (int z = 0; z < NEIGHBOR_OFFSETS.getCount(); z++) {
        int3 neighbor_pos = groupPos + NEIGHBOR_OFFSETS[z];
        int neighbor_map_index = GlobalLights.GetMapIndex(neighbor_pos);
        if (neighbor_map_index < 0) continue;

        scanBin(localIndex, groupPos, GlobalLightMap[neighbor_map_index], true, (worldOffset + neighbor_pos) * 8);
    }
}

void scanBin(const in uint localIndex, const in uint3 groupPos, const in VoxelLightRange range, const in bool testReach, const in int3 binMin) {
    SectionBounds sectionBounds;
    sectionBounds.worldMin = binMin;
    sectionBounds.worldMax = sectionBounds.worldMin + 8;

    for (uint i = localIndex; i < uint(range.count); i += GroupSize) {
        var light = GlobalLightIndex[range.start + i];

        if (testReach) {
            float lightRange = getLightColorRange(ap.blocks[light.blockId]).a;
            if (!sectionBounds.intersectsSphere(light.voxelPos + 0.5, lightRange)) continue;
        }

        addToReservoir(light, groupPos);
    }
}

void addToReservoir(const in VoxelLight light, const in uint3 groupPos) {
    uint candidateIndex = shared_counter.increment();
    if (candidateIndex < MaxLocalLightCount) {
        shared_lights[candidateIndex] = light;
        return;
    }

    uint slot = randomReservoirSlot(candidateIndex, groupPos);
    if (slot < MaxLocalLightCount) {
        shared_lights[slot] = light;
    }
}

uint randomReservoirSlot(const in uint candidateIndex, const in uint3 groupPos) {
    uint bound = candidateIndex + 1u;
    uint threshold = -bound % bound;

    for (uint salt = 0u; ; salt++) {
        uint random = BlueNoise::hash31(groupPos ^ uint3(candidateIndex, salt, candidateIndex + salt));
        if (random >= threshold) return random % bound;
    }
}

void copyReservoirToLocalList(const in uint localIndex, const in uint storedCount) {
    int stride = int(ceil(storedCount / float(GroupSize)));

    for (int i = 0; i < stride; i++) {
        uint i_local = localIndex * stride + i;
        if (i_local >= storedCount) break;

        uint i_global = global_start + i_local;
        if (i_global >= LightList_LocalMaxLightCount) break;
        LocalLightIndex[i_global] = shared_lights[i_local];
    }
}

struct SectionBounds {
    float3 worldMin;
    float3 worldMax;

    bool intersectsSphere(const in float3 worldPos, const in float radius) {
        float3 closestPoint = clamp(worldPos, worldMin, worldMax);

        float3 delta = worldPos - closestPoint;
        return dot(delta, delta) < pow2(radius);
    }
};

// static const int3 NEIGHBOR_OFFSETS[26] = {
//     // --- 6 Face Neighbors (Distance = 1.0) ---
//     int3( 1,  0,  0), int3(-1,  0,  0),
//     int3( 0,  1,  0), int3( 0, -1,  0),
//     int3( 0,  0,  1), int3( 0,  0, -1),

//     // --- 12 Edge Neighbors (Distance ~1.41) ---
//     int3( 1,  1,  0), int3( 1, -1,  0),
//     int3(-1,  1,  0), int3(-1, -1,  0),
//     int3( 1,  0,  1), int3( 1,  0, -1),
//     int3(-1,  0,  1), int3(-1,  0, -1),
//     int3( 0,  1,  1), int3( 0,  1, -1),
//     int3( 0, -1,  1), int3( 0, -1, -1),

//     // --- 8 Corner Neighbors (Distance ~1.73) ---
//     int3( 1,  1,  1), int3( 1,  1, -1),
//     int3( 1, -1,  1), int3( 1, -1, -1),
//     int3(-1,  1,  1), int3(-1,  1, -1),
//     int3(-1, -1,  1), int3(-1, -1, -1)
// };

static const int3 NEIGHBOR_OFFSETS[124] = {
    // Squared distance = 1
    int3(-1,  0,  0),
    int3( 0, -1,  0),
    int3( 0,  0, -1),
    int3( 0,  0,  1),
    int3( 0,  1,  0),
    int3( 1,  0,  0),
    // Squared distance = 2
    int3(-1, -1,  0),
    int3(-1,  0, -1),
    int3(-1,  0,  1),
    int3(-1,  1,  0),
    int3( 0, -1, -1),
    int3( 0, -1,  1),
    int3( 0,  1, -1),
    int3( 0,  1,  1),
    int3( 1, -1,  0),
    int3( 1,  0, -1),
    int3( 1,  0,  1),
    int3( 1,  1,  0),
    // Squared distance = 3
    int3(-1, -1, -1),
    int3(-1, -1,  1),
    int3(-1,  1, -1),
    int3(-1,  1,  1),
    int3( 1, -1, -1),
    int3( 1, -1,  1),
    int3( 1,  1, -1),
    int3( 1,  1,  1),
    // Squared distance = 4
    int3(-2,  0,  0),
    int3( 0, -2,  0),
    int3( 0,  0, -2),
    int3( 0,  0,  2),
    int3( 0,  2,  0),
    int3( 2,  0,  0),
    // Squared distance = 5
    int3(-2, -1,  0),
    int3(-2,  0, -1),
    int3(-2,  0,  1),
    int3(-2,  1,  0),
    int3(-1, -2,  0),
    int3(-1,  0, -2),
    int3(-1,  0,  2),
    int3(-1,  2,  0),
    int3( 0, -2, -1),
    int3( 0, -2,  1),
    int3( 0, -1, -2),
    int3( 0, -1,  2),
    int3( 0,  1, -2),
    int3( 0,  1,  2),
    int3( 0,  2, -1),
    int3( 0,  2,  1),
    int3( 1, -2,  0),
    int3( 1,  0, -2),
    int3( 1,  0,  2),
    int3( 1,  2,  0),
    int3( 2, -1,  0),
    int3( 2,  0, -1),
    int3( 2,  0,  1),
    int3( 2,  1,  0),
    // Squared distance = 6
    int3(-2, -1, -1),
    int3(-2, -1,  1),
    int3(-2,  1, -1),
    int3(-2,  1,  1),
    int3(-1, -2, -1),
    int3(-1, -2,  1),
    int3(-1, -1, -2),
    int3(-1, -1,  2),
    int3(-1,  1, -2),
    int3(-1,  1,  2),
    int3(-1,  2, -1),
    int3(-1,  2,  1),
    int3( 1, -2, -1),
    int3( 1, -2,  1),
    int3( 1, -1, -2),
    int3( 1, -1,  2),
    int3( 1,  1, -2),
    int3( 1,  1,  2),
    int3( 1,  2, -1),
    int3( 1,  2,  1),
    int3( 2, -1, -1),
    int3( 2, -1,  1),
    int3( 2,  1, -1),
    int3( 2,  1,  1),
    // Squared distance = 8
    int3(-2, -2,  0),
    int3(-2,  0, -2),
    int3(-2,  0,  2),
    int3(-2,  2,  0),
    int3( 0, -2, -2),
    int3( 0, -2,  2),
    int3( 0,  2, -2),
    int3( 0,  2,  2),
    int3( 2, -2,  0),
    int3( 2,  0, -2),
    int3( 2,  0,  2),
    int3( 2,  2,  0),
    // Squared distance = 9
    int3(-2, -2, -1),
    int3(-2, -2,  1),
    int3(-2, -1, -2),
    int3(-2, -1,  2),
    int3(-2,  1, -2),
    int3(-2,  1,  2),
    int3(-2,  2, -1),
    int3(-2,  2,  1),
    int3(-1, -2, -2),
    int3(-1, -2,  2),
    int3(-1,  2, -2),
    int3(-1,  2,  2),
    int3( 1, -2, -2),
    int3( 1, -2,  2),
    int3( 1,  2, -2),
    int3( 1,  2,  2),
    int3( 2, -2, -1),
    int3( 2, -2,  1),
    int3( 2, -1, -2),
    int3( 2, -1,  2),
    int3( 2,  1, -2),
    int3( 2,  1,  2),
    int3( 2,  2, -1),
    int3( 2,  2,  1),
    // Squared distance = 12
    int3(-2, -2, -2),
    int3(-2, -2,  2),
    int3(-2,  2, -2),
    int3(-2,  2,  2),
    int3( 2, -2, -2),
    int3( 2, -2,  2),
    int3( 2,  2, -2),
    int3( 2,  2,  2),
};
