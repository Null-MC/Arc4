public module global_lights;

import aperture;


extern static const int GlobalMaxLightCount;
extern static const int GlobalMaxIndexCount;
static const int MaxLocalLightCount = 256;

extern static const int GlobalLight_SectionSizeX;
extern static const int GlobalLight_SectionSizeY;
extern static const int GlobalLight_SectionSizeZ;

static const int3 GlobalLight_SectionSize = int3(GlobalLight_SectionSizeX, GlobalLight_SectionSizeY, GlobalLight_SectionSizeZ);

RWStructuredBuffer<Atomic<uint>> GlobalLightCounter;
RWStructuredBuffer<VoxelLight> GlobalLightIndex;

RWStructuredBuffer<VoxelLightRange> GlobalLightMap;

struct VoxelLight {
    int3 voxelPos;
    int blockId;
}

struct VoxelLightRange {
    int start;
    int count;
}

namespace GlobalLights {

    float3 getSectionPosition(float3 localPos) {
        float3 cameraOffset = fract(ap.camera.position / 8.0);
        return localPos/8.0 + cameraOffset + GlobalLight_SectionSize/2;
    }

    int GetMapIndex(int3 sectionPos) {
        const int3 flatten = int3(1, GlobalLight_SectionSizeX, GlobalLight_SectionSizeX * GlobalLight_SectionSizeY);

        if (!all(clamp(sectionPos, 0, GlobalLight_SectionSize - 1) == sectionPos)) return -1;
        return dot(sectionPos, flatten);
    }

}
