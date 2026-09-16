public module DDA;

import aperture;
import lib.common;

namespace DDA {

    public void init(out float3 stepSizes, out float3 nextDist, const in float3 currPos, const in float3 localDir) {
        float3 stepDir = sign(localDir);
        stepSizes = rcp(abs(localDir));

        nextDist = stepDir * 0.5 + 0.5;
        nextDist = (nextDist - fract(currPos)) / localDir;
    }

    public float3 step(out float3 stepAxis, inout float3 nextDist, const in float3 stepSizes, const in float3 localDir) {
        float closestDist = minOf(nextDist);
        stepAxis = float3(nextDist <= closestDist);

        nextDist -= closestDist;
        nextDist = fma(stepSizes, stepAxis, nextDist);

        return localDir * closestDist;
    }

    float trace(out float3 hit_normal, const in float3 localPos, const in float3 localDir, const in int maxStepCount) {
        float3 cameraFract = fract(ap.camera.position);

        float3 stepAxis = 0.0;
        float3 stepSizes, nextDist;
        float3 currPos = localPos + cameraFract;
        DDA::init(stepSizes, nextDist, currPos, localDir);

        for (uint i = 0; i < maxStepCount; i++) {
            float3 stepAxisNext;
            float3 step = DDA::step(stepAxisNext, nextDist, stepSizes, localDir);

            float3 tracePos = currPos + 0.5*step - cameraFract;
            int3 voxelPos = int3(floor(tracePos + ap.camera.position));
            var voxelBlock = ap.blocks[ap.voxel[voxelPos]];

            if (voxelBlock.isFullBlock) {
                hit_normal = -sign(localDir) * stepAxis;
                return distance(currPos - cameraFract, localPos);
            }

            currPos += step;
            stepAxis = stepAxisNext;
        }

        hit_normal = 0.0;
        return -1.0;
    }

}

// public struct DDA_tracer {
//     private float3 cameraFract, localDir;
//     private float3 stepSizes, nextDist, stepAxis;
//     private float3 currPos;
//     private float3 currStep;
//     private float3 stepAxisNext;

//     public __init(const in float3 localPos, const in float3 localDir) {
//         this.localDir = localDir;
//         this.cameraFract = fract(ap.camera.position);

//         this.currPos = localPos + this.cameraFract;
//         DDA::init(stepSizes, nextDist, currPos, localDir);

//         this.currStep = DDA::step(stepAxisNext, nextDist, stepSizes, localDir);
//     }

//     public void next() {
//         currPos += currStep;
//         stepAxis = stepAxisNext;

//         currStep = DDA::step(stepAxisNext, nextDist, stepSizes, localDir);
//     }
// };
