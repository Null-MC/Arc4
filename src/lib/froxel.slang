public module froxel;

import aperture;
import lib.common;
// import lib.sampling.depth;

extern static const int Froxel_Width = 0;
extern static const int Froxel_Height = 0;
extern static const int Froxel_Depth = 0;

// static const float Froxel_MaxDist = 80.0;

static const uint3 Froxel_Resolution = uint3(Froxel_Width, Froxel_Height, Froxel_Depth);


float3 Froxel_GetNdcPosition(const in float3 bufferPos) {
    float3 ndcPos = bufferPos / Froxel_Resolution;

    ndcPos.z = pow3(ndcPos.z);
    
    // ndcPos.z = delinearizeDepth(ndcPos.z * Froxel_MaxDist, ap.camera.near, ap.camera.far);

    ndcPos.xy = ndcPos.xy * 2.0 - 1.0;

    return ndcPos;
}

float3 Froxel_GetBufferPosition(in float3 ndcPos) {
    // ndcPos.z = linearizeDepth(ndcPos.z, ap.camera.near, ap.camera.far) / Froxel_MaxDist;

    ndcPos.xy = ndcPos.xy * 0.5 + 0.5;

    ndcPos.z = pow(ndcPos.z, (1.0/3.0));

    return ndcPos * Froxel_Resolution;
}

bool Froxel_InBufferBounds(const in float3 bufferPos) {
    return all(clamp(bufferPos, 0.5, Froxel_Resolution - 0.5) == bufferPos);
}
