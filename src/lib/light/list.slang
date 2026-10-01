public module light_list;

import aperture;


extern static const int LightList_GlobalMaxLightCount;
extern static const int LightList_LocalMaxLightCount;
extern static const int LightList_MaxIndexCount;
static const int MaxLocalLightCount = 256;

extern static const int LightList_SectionSizeX;
extern static const int LightList_SectionSizeY;
extern static const int LightList_SectionSizeZ;

static const int3 LightList_SectionSize = int3(LightList_SectionSizeX, LightList_SectionSizeY, LightList_SectionSizeZ);

RWStructuredBuffer<LightListCounterData> LightListCounters;

RWStructuredBuffer<VoxelLight> GlobalLightIndex;
RWStructuredBuffer<VoxelLightRange> GlobalLightMap;

RWStructuredBuffer<VoxelLight> LocalLightIndex;
RWStructuredBuffer<VoxelLightRange> LocalLightMap;

struct LightListCounterData {
    Atomic<uint> global;
    Atomic<uint> local;
};

struct VoxelLight {
    int3 voxelPos;
    int blockId;
};

struct VoxelLightRange {
    int start;
    int count;
};

namespace GlobalLights {

    float3 getSectionPosition(float3 localPos) {
        float3 cameraOffset = fract(ap.camera.position / 8.0);
        return localPos/8.0 + cameraOffset + LightList_SectionSize/2;
    }

    int GetMapIndex(int3 sectionPos) {
        const int3 flatten = int3(1, LightList_SectionSizeX, LightList_SectionSizeX * LightList_SectionSizeY);

        if (!all(clamp(sectionPos, 0, LightList_SectionSize - 1) == sectionPos)) return -1;
        return dot(sectionPos, flatten);
    }

}
