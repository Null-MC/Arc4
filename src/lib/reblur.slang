public module reblur;

import aperture;
import lib.common;


// 8-neighborhood used for disocclusion/plane-distance checks.
static const int2 sample_offsets[8] = {
    int2(-1,-1), int2( 0,-1), int2( 1,-1),
    int2(-1, 0),               int2( 1, 0),
    int2(-1, 1), int2( 0, 1), int2( 1, 1),
};

namespace ReBLUR {

    // Reprojects a clip-space position from the current frame into the previous frame's clip space.
    float3 reprojectLast(const in float3 clipPos) {
        float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
        float3 localPos = mul3(ap.camera.viewInv, viewPos);

        float3 localPosLast = localPos + (ap.camera.position - ap.temporal.position);
        float3 viewPosLast = mul3(ap.temporal.view, localPosLast);
        return mul_project(ap.temporal.projection, viewPosLast);
    }

    // Reprojects a clip-space position from the previous frame back into the current frame's clip space.
    float3 reprojectCurrent(const in float3 clipPosLast) {
        float3 viewPosLast = mul_project(ap.temporal.projectionInv, clipPosLast);
        float3 localPosLast = mul3(ap.temporal.viewInv, viewPosLast);

        float3 localPos = localPosLast - (ap.camera.position - ap.temporal.position);
        float3 viewPos = mul3(ap.camera.view, localPos);
        return mul_project(ap.camera.projection, viewPos);
    }

    // Packs a world-space hit distance into [0,1], compressing distant (smooth) bounces toward 1,
    // following the same convention NRD uses to store hit distance in the signal's alpha channel.
    float normalizeHitDistance(const in float hitDistance, const in float viewZ) {
        return saturate(hitDistance / (hitDistance + max(viewZ, 1.0)));
    }

    // Vogel spiral: evenly fills a disc with `count` taps using a low-discrepancy pattern.
    float2 vogelDiscOffset(const in int index, const in int count, const in float rotation) {
        static const float GoldenAngle = 2.39996323;
        float r = sqrt((index + 0.5) / count);
        float theta = index * GoldenAngle + rotation;
        return r * float2(cos(theta), sin(theta));
    }

    // Blur radius grows with signal noise: short accumulation history, or a smooth/distant bounce.
    float computeBlurRadius(const in float baseRadius, const in float frameCount, const in float maxFrameCount, const in float normHitDistance) {
        float convergence = saturate(frameCount / maxFrameCount);
        float historyScale = lerp(1.0, 0.15, convergence);
        float hitDistScale = lerp(0.4, 1.5, normHitDistance);
        return baseRadius * historyScale * hitDistScale;
    }

    // Bilateral edge stop: rejects taps landing on a different surface (normal mismatch or depth-plane offset).
    float computeEdgeWeight(const in float3 centerViewPos, const in float3 centerNormal, const in float3 tapViewPos, const in float3 tapNormal) {
        float normalWeight = pow(max(dot(centerNormal, tapNormal), 0.0), 32.0);

        float planeDistance = abs(dot(centerNormal, tapViewPos - centerViewPos));
        float depthWeight = exp(-planeDistance * planeDistance * 64.0 / max(lengthSq(centerViewPos), 1e-4));

        return normalWeight * depthWeight;
    }
}
