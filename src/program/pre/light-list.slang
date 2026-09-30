import aperture;
import lib.common;
import lib.global_lights;


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
    GlobalLightCounter[0].store(0u);
}

[[shader("compute")]]
[numthreads(8,4,8)]
void main(ComputeInput input) {
    // Intialize shared counter
    if (input.localIndex == 0u) {
        shared_counter.store(0u);
    }

    GroupMemoryBarrierWithGroupSync();

    // Sample voxels for lights
    int3 worldOffset = int3(floor(ap.camera.position / 8.0)) - GlobalLight_SectionSize/2;
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
        global_start = GlobalLightCounter[0].add(count);
    }

    GroupMemoryBarrierWithGroupSync();

    // Copy shared lights to global light list
    int map_index = GlobalLights.GetMapIndex(input.groupPos);
    if (map_index < 0) return;

    GlobalLightMap[map_index] = VoxelLightRange(global_start, count);

    [ForceUnroll]
    for (int i = 0; i < 2; i++) {
        uint i_local = input.localIndex * 2 + i;
        if (i_local >= count) break;

        uint i_global = global_start + i_local;
        if (i_global >= GlobalMaxLightCount) break;

        GlobalLightIndex[i_global] = shared_lights[i_local];
    }
}

void insertLocalLight(int3 localPos, int blockId) {
    int i = shared_counter.increment();
    if (i >= MaxLocalLightCount) return;

    shared_lights[i] = VoxelLight(localPos, blockId);
}
