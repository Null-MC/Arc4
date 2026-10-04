import aperture;
import lib.common;
import lib.noise.blue;
import lib.light.data;
import lib.light.list;


static const int GroupSize = 8*4*8;

groupshared VoxelLight shared_lights[MaxLocalLightCount];
groupshared uint shared_count;
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
        buildLocalReservoir(input.groupPos);
        global_start = LightListCounters[0].local.add(min(shared_count, MaxLocalLightCount));
    }

    GroupMemoryBarrierWithGroupSync();

    uint stored_count = min(shared_count, MaxLocalLightCount);
    LocalLightMap[map_index] = VoxelLightRange(global_start, shared_count);
    copyReservoirToLocalList(input.localIndex, stored_count);
}

void buildLocalReservoir(const in uint3 groupPos) {
    uint candidate_count = 0u;
    int map_index = GlobalLights.GetMapIndex(groupPos);
    var global_range = GlobalLightMap[map_index];

    for (uint i = 0u; i < uint(global_range.count); i++) {
        addToReservoir(GlobalLightIndex[global_range.start + i], candidate_count, groupPos);
    }

    int3 worldOffset = int3(floor(ap.camera.position / 8.0)) - LightList_SectionSize/2;
    SectionBounds sectionBounds;

    for (int z = 0; z < NEIGHBOR_OFFSETS.getCount(); z++) {
        int3 neighbor_pos = groupPos + NEIGHBOR_OFFSETS[z];
        int neighbor_map_index = GlobalLights.GetMapIndex(neighbor_pos);
        if (neighbor_map_index < 0) continue;

        var neighbor_range = GlobalLightMap[neighbor_map_index];

        for (uint i = 0u; i < uint(neighbor_range.count); i++) {
            var light = GlobalLightIndex[neighbor_range.start + i];
            float lightRange = getLightColorRange(ap.blocks[light.blockId]).a;

            sectionBounds.worldMin = (worldOffset + neighbor_pos) * 8;
            sectionBounds.worldMax = sectionBounds.worldMin + 8;

            if (!sectionBounds.intersectsSphere(light.voxelPos + 0.5, lightRange)) continue;
            addToReservoir(light, candidate_count, groupPos);
        }
    }

    shared_count = candidate_count;
}

void addToReservoir(const in VoxelLight light, inout uint candidateCount, const in uint3 groupPos) {
    uint candidateIndex = candidateCount++;
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
