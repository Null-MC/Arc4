import aperture;
import lib.common;
import lib.light.list;


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
[numthreads(1)]
void clear() {
    LightListCounters[0].global.store(0u);
    LightListCounters[0].local.store(0u);
}

[[shader("compute")]]
[numthreads(8,4,8)]
void main(ComputeInput input) {
    int map_index = GlobalLights.GetMapIndex(input.groupPos);
    if (map_index < 0) return;

    // Intialize shared counter
    if (input.localIndex == 0u) {
        shared_counter.store(0u);
    }

    GroupMemoryBarrierWithGroupSync();

    // Sample voxels for lights
    int3 worldOffset = int3(floor(ap.camera.position / 8.0)) - LightList_SectionSize/2;
    int3 worldPos = worldOffset*8 + input.globalPos * int3(1,2,1);

    int3 v1 = worldPos;
    var blockId1 = ap.voxel[v1];
    if (ap.blocks[blockId1].emission > 0) {
        insertLocalLight(v1, blockId1);
    }
    
    int3 v2 = worldPos + int3(0,1,0);
    var blockId2 = ap.voxel[v2];
    if (ap.blocks[blockId2].emission > 0) {
        insertLocalLight(v2, blockId2);
    }

    GroupMemoryBarrierWithGroupSync();

    // Populate shared global index
    uint count = shared_counter.load();
    count = min(count, MaxLocalLightCount);

    if (input.localIndex == 0u) {
        global_start = LightListCounters[0].global.add(count);
    }

    GroupMemoryBarrierWithGroupSync();

    // avoid exceeding the global light list capacity
    count = min(count, LightList_GlobalMaxLightCount - global_start);
    count = max(count, 0);

    // Copy shared lights to global light list
    GlobalLightMap[map_index] = VoxelLightRange(global_start, count);
    if (count == 0) return;

    [ForceUnroll]
    for (int i = 0; i < 2; i++) {
        uint i_local = input.localIndex * 2 + i;
        if (i_local >= count) break;

        uint i_global = global_start + i_local;
        if (i_global >= LightList_GlobalMaxLightCount) break;

        GlobalLightIndex[i_global] = shared_lights[i_local];
    }
}

void insertLocalLight(int3 localPos, int blockId) {
    int i = shared_counter.increment();
    if (i >= LightList_LocalMaxLightCount) return;

    shared_lights[i] = VoxelLight(localPos, blockId);
}
