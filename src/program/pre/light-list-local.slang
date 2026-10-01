import aperture;
import lib.common;
import lib.light.data;
import lib.light.list;


static const int GroupSize = 8*4*8;

groupshared Atomic<uint> shared_counter;
groupshared VoxelLight shared_lights[MaxLocalLightCount];
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

    // Intialize shared counter
    if (input.localIndex == 0u) {
        shared_counter.store(0u);
    }

    GroupMemoryBarrierWithGroupSync();

    // Sample neighbor bins for lights
    int3 worldOffset = int3(floor(ap.camera.position / 8.0)) - LightList_SectionSize/2;
    SectionBounds sectionBounds;

    for (int z = 0; z < 26; z++) {
        int3 neighbor_pos = input.groupPos + NEIGHBOR_OFFSETS[z];
        int neighbor_map_index = GlobalLights.GetMapIndex(neighbor_pos);
        if (neighbor_map_index < 0) continue;

        var neighbor_range = GlobalLightMap[neighbor_map_index];

        int stride = int(ceil(neighbor_range.count / float(GroupSize)));

        for (int i = 0; i < stride; i++) {
            int i_local = input.localIndex * stride + i;
            if (i_local >= neighbor_range.count) break;

            // Copy neighbor lights to shared_lights
            var light = GlobalLightIndex[neighbor_range.start + i_local];
            var block = ap.blocks[light.blockId];

            int blockId = block.customId;
            float lightRange = getLightColorRange(block).a;

            // test if light actually reaches this bin!
            sectionBounds.worldMin = (worldOffset + neighbor_pos) * 8;
            sectionBounds.worldMax = sectionBounds.worldMin + 8;

            if (!sectionBounds.intersectsSphere(light.voxelPos + 0.5, lightRange)) continue;

            uint i_shared = shared_counter.increment();
            if (i_shared >= MaxLocalLightCount) break;

            shared_lights[i_shared] = light;
        }
    }

    GroupMemoryBarrierWithGroupSync();

    // Populate shared global index
    var global_range = GlobalLightMap[map_index];

    uint local_count = shared_counter.load();
    uint total_count = min(local_count + global_range.count, MaxLocalLightCount);
    local_count = max(total_count - global_range.count, 0);

    if (input.localIndex == 0u) {
        global_start = LightListCounters[0].local.add(total_count);
    }

    GroupMemoryBarrierWithGroupSync();

    // Create local light list mapping
    LocalLightMap[map_index] = VoxelLightRange(global_start, total_count);

    if (total_count == 0) return;

    // Copy lights from global list to local list
    copyGlobalToLocalList(input.localIndex, global_range);

    // Copy new local lights to local light list
    if (local_count <= 0) return;

    copyLocalToLocalList(input.localIndex, local_count, global_range.count);
}

void copyGlobalToLocalList(const in uint localIndex, const in VoxelLightRange global_range) {
    int stride = int(ceil(global_range.count / float(GroupSize)));

    for (uint i = 0; i < stride; i++) {
        uint i_local = localIndex * stride + i;
        if (i_local >= global_range.count) break;

        // TODO: further validate in/out index is not OOB?

        LocalLightIndex[global_start + i_local] = GlobalLightIndex[global_range.start + i_local];
    }
}

void copyLocalToLocalList(const in uint localIndex, const in uint local_count, const in uint global_count) {
    int stride = int(ceil(local_count / float(GroupSize)));

    for (int i = 0; i < stride; i++) {
        uint i_local = localIndex * stride + i;
        if (i_local >= local_count) break;

        uint i_global = global_start + global_count + i_local;
        if (i_global >= LightList_GlobalMaxLightCount) break;

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

static const int3 NEIGHBOR_OFFSETS[26] = {
    // --- 6 Face Neighbors (Distance = 1.0) ---
    int3( 1,  0,  0), int3(-1,  0,  0),
    int3( 0,  1,  0), int3( 0, -1,  0),
    int3( 0,  0,  1), int3( 0,  0, -1),

    // --- 12 Edge Neighbors (Distance ~1.41) ---
    int3( 1,  1,  0), int3( 1, -1,  0),
    int3(-1,  1,  0), int3(-1, -1,  0),
    int3( 1,  0,  1), int3( 1,  0, -1),
    int3(-1,  0,  1), int3(-1,  0, -1),
    int3( 0,  1,  1), int3( 0,  1, -1),
    int3( 0, -1,  1), int3( 0, -1, -1),

    // --- 8 Corner Neighbors (Distance ~1.73) ---
    int3( 1,  1,  1), int3( 1,  1, -1),
    int3( 1, -1,  1), int3( 1, -1, -1),
    int3(-1,  1,  1), int3(-1,  1, -1),
    int3(-1, -1,  1), int3(-1, -1, -1)
};
