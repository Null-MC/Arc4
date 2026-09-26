import aperture;
import settings;
import lib.common;
import lib.octohedral;
import lib.pbr.material;


[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuse_write;

[[vk::image_format("r8ui")]]
RWTexture2D<uint> texDiffuseCounter_write;

Texture2D<float4> texDiffuse_read;
Texture2D<float4> texDiffuseHistory_read;
Texture2D<uint> texDiffuseCounter_read;
Texture2D<float2> texNormalHistory_read;
Texture2D<float> texDepthHistory_read;

Texture2D<half4> texDeferNormal;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float3 diffuse_now = texDiffuse_read[globalPos].rgb;
    float3 diffuse_final;
    uint historyCounter;
    
    if (ap.timing.frameCounter > 0) {
        float depth_now = ap.depth[globalPos];
        half4 normalData_now = texDeferNormal[globalPos];
        float3 geo_normal_now = octohedral::decode(normalData_now.xy);

        float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
        float3 clipPos = float3(texcoord * 2.0 - 1.0, depth_now);
        float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
        float3 localPos = mul3(ap.camera.viewInv, viewPos);

        float3 localPosLast = localPos + (ap.camera.position - ap.temporal.position);
        float3 viewPosLast = mul3(ap.temporal.view, localPosLast);
        float3 clipPosLast = mul_project(ap.temporal.projection, viewPosLast);
        float2 texcoordLast = clipPosLast.xy * 0.5 + 0.5;

        // reproject previous depth
        clipPosLast.z = texDepthHistory_read.Sample(apt_linearSampler, texcoordLast).r;
        viewPosLast = mul_project(ap.temporal.projectionInv, clipPosLast);
        localPosLast = mul3(ap.temporal.viewInv, viewPosLast);
        localPosLast -= ap.camera.position - ap.temporal.position;

        // history counter and rejection
        historyCounter = texDiffuseCounter_read.Sample(apt_nearestSampler, texcoordLast).r;

        // reject if the motion between frames is too large
        if (length(localPosLast - localPos) > 0.02 * length(localPos)) {
            texcoordLast = (floor(texcoordLast * ap.game.renderSize) + 0.5) / ap.game.renderSize;
            historyCounter = 0;
        }

        // reject if offscreen
        if (!all(saturate(texcoordLast) == texcoordLast)) historyCounter = 0;

        // TODO: reject normal changes
        half2 normalData_last = texNormalHistory_read.Sample(apt_nearestSampler, texcoordLast);
        float3 geo_normal_last = octohedral::decode(normalData_last);
        if (dot(geo_normal_now, geo_normal_last) < 0.965) historyCounter = 0;

        // reject if the camera has moved/rotated at all
        // if (!all(ap.camera.position == ap.temporal.position)) historyCounter = 0;
        // if (!all(ap.camera.viewInv[2].xyz == ap.temporal.viewInv[2].xyz)) historyCounter = min(historyCounter, 8);

        // temporal blending
        historyCounter = clamp(historyCounter, 0, 120);

        // TODO: replace with manually weighted linear sampling
        // float3 diffuse_last = texDiffuseHistory_read.Sample(apt_linearSampler, texcoordLast).rgb;
        float3 diffuse_last = SampleHistoryValid(texcoordLast, geo_normal_now);

        diffuse_final = lerp(diffuse_last, diffuse_now, rcp(historyCounter + 1.0));
    }
    else {
        diffuse_final = diffuse_now;
        historyCounter = 0;
    }

    texDiffuse_write[globalPos] = diffuse_final;
    texDiffuseCounter_write[globalPos] = historyCounter;
}

float3 SampleHistoryValid(float2 texcoordLast, float3 geo_normal) {
    // Convert to unnormalized texture coordinates in the history buffer
    float2 uvSize = float2(ap.game.renderSize);
    float2 texelPos = texcoordLast * uvSize - 0.5;
    int2 baseTexel = int2(floor(texelPos));
    float2 f = frac(texelPos);

    // Calculate bilinear weights for a standard 2x2 quad
    float w00 = (1.0 - f.x) * (1.0 - f.y);
    float w10 = f.x * (1.0 - f.y);
    float w01 = (1.0 - f.x) * f.y;
    float w11 = f.x * f.y;

    // Manually load the 4 texels from both history color and history depth
    int2 p00 = clamp(baseTexel + int2(0, 0), 0, ap.game.renderSize - 1);
    int2 p10 = clamp(baseTexel + int2(1, 0), 0, ap.game.renderSize - 1);
    int2 p01 = clamp(baseTexel + int2(0, 1), 0, ap.game.renderSize - 1);
    int2 p11 = clamp(baseTexel + int2(1, 1), 0, ap.game.renderSize - 1);

    float3 c00 = texDiffuseHistory_read[p00].rgb;
    float3 c10 = texDiffuseHistory_read[p10].rgb;
    float3 c01 = texDiffuseHistory_read[p01].rgb;
    float3 c11 = texDiffuseHistory_read[p11].rgb;

    // float d00 = texDepthHistory_read[p00].r;
    // float d10 = texDepthHistory_read[p10].r;
    // float d01 = texDepthHistory_read[p01].r;
    // float d11 = texDepthHistory_read[p11].r;

    float3 n00 = octohedral::decode(texNormalHistory_read[p00].xy);
    float3 n10 = octohedral::decode(texNormalHistory_read[p10].xy);
    float3 n01 = octohedral::decode(texNormalHistory_read[p01].xy);
    float3 n11 = octohedral::decode(texNormalHistory_read[p11].xy);

    // Validate each tap against the current depth. 
    // Using a linearized or depth-ratio threshold prevents background bleeding.
    // float depthThreshold = 0.01 * (ap.camera.near / max(depth_now, 1e-5)); 
    
    // float v00 = (abs(d00 - depth_now) < depthThreshold) ? 1.0 : 0.0;
    // float v10 = (abs(d10 - depth_now) < depthThreshold) ? 1.0 : 0.0;
    // float v01 = (abs(d01 - depth_now) < depthThreshold) ? 1.0 : 0.0;
    // float v11 = (abs(d11 - depth_now) < depthThreshold) ? 1.0 : 0.0;

    float v00 = (dot(n00, geo_normal) > 0.965) ? 1.0 : 0.0;
    float v10 = (dot(n10, geo_normal) > 0.965) ? 1.0 : 0.0;
    float v01 = (dot(n01, geo_normal) > 0.965) ? 1.0 : 0.0;
    float v11 = (dot(n11, geo_normal) > 0.965) ? 1.0 : 0.0;

    // Apply validation mask to weights
    w00 *= v00;
    w10 *= v10;
    w01 *= v01;
    w11 *= v11;

    float sumWeights = w00 + w10 + w01 + w11;

    // If at least one pixel in the bilinear footprint is valid, re-normalize weights
    if (sumWeights > 0.001) {
        return (c00 * w00 + c10 * w10 + c01 * w01 + c11 * w11) / sumWeights;
    }
    
    // Fallback: If the whole footprint is invalid (complete disocclusion), 
    // return the nearest neighbor tap or a value that will trigger color clipping later
    return c00; 
}
