import aperture;
import settings;
import lib.common;
import lib.octohedral;
import lib.pbr.material;


static const int MAX_HISTORY = 40;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuse_write;

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texDiffuseFast_write;

[[vk::image_format("r8ui")]]
RWTexture2D<uint> texDiffuseCounter_write;

Texture2D<float4> texDiffuse_read;
Texture2D<float4> texDiffuseHistory_read;
Texture2D<float4> texDiffuseFastHistory_read;
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
    float3 diffuse_fast;
    uint historyCounter;
    
    if (ap.timing.frameCounter > 0) {
        float depth_now = ap.depth[globalPos];
        half4 normalData_now = texDeferNormal[globalPos];
        float3 geo_normal_now = octohedral::decode(normalData_now.xy);
        float3 tex_normal_now = octohedral::decode(normalData_now.zw);

        float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;

        // if (userSettings.TAA_Enabled) {
        //     texcoord -= scene.TAA_jitter;
        // }

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
        float viewDist = length(viewPos);

        // reject if the motion between frames is too large
        if (length(localPosLast - localPos) > 0.04 * viewDist) {
            // texcoordLast = (floor(texcoordLast * ap.game.renderSize) + 0.5) / ap.game.renderSize;
            historyCounter = 0;
        }

        // reject if offscreen
        if (!all(saturate(texcoordLast) == texcoordLast)) historyCounter = 0;

        // reject normal changes
        half2 normalData_last = texNormalHistory_read.Sample(apt_nearestSampler, texcoordLast);
        float3 normal_last = octohedral::decode(normalData_last);

        float normalWeight = 16.0 / (16.0 + viewDist);
        if (dot(tex_normal_now, normal_last) < normalWeight) historyCounter = 0;

        // reject if the camera has moved/rotated at all
        // if (!all(ap.camera.position == ap.temporal.position)) historyCounter = 0;
        // if (!all(ap.camera.viewInv[2].xyz == ap.temporal.viewInv[2].xyz)) historyCounter = min(historyCounter, 8);

        // temporal blending
        historyCounter = clamp(historyCounter, 0, MAX_HISTORY);

        float3 diffuse_last;
        float3 diffuse_fast_last;
        SampleHistoryValid(texcoordLast, tex_normal_now, diffuse_last, diffuse_fast_last);

        if (historyCounter == 0) {
            diffuse_final = diffuse_now;
            diffuse_fast = diffuse_now;
        }
        else if (userSettings.Lighting_FastClamp) {
            diffuse_fast = lerp(
                diffuse_fast_last,
                diffuse_now,
                rcp(min(historyCounter, uint(userSettings.Lighting_FastClampFrames)) + 1.0));

            diffuse_final = lerp(diffuse_last, diffuse_now, rcp(historyCounter + 1.0));
            float3 neighborhoodMin;
            float3 neighborhoodMax;
            CalculateFastHistoryBounds(globalPos, diffuse_fast, neighborhoodMin, neighborhoodMax);
            diffuse_final = clamp(diffuse_final, neighborhoodMin, neighborhoodMax);
        }
        else {
            diffuse_final = lerp(diffuse_last, diffuse_now, rcp(historyCounter + 1.0));
            diffuse_fast = diffuse_final;
        }
    }
    else {
        diffuse_final = diffuse_now;
        diffuse_fast = diffuse_now;
        historyCounter = 0;
    }

    texDiffuse_write[globalPos] = diffuse_final;
    texDiffuseFast_write[globalPos] = diffuse_fast;
    texDiffuseCounter_write[globalPos] = historyCounter;
}

void CalculateFastHistoryBounds(int2 position, float3 center, out float3 minimum, out float3 maximum) {
    float3 firstMoment = 0.0;
    float3 secondMoment = 0.0;

    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            int2 samplePosition = clamp(position + int2(x, y), 0, ap.game.renderSize - 1);
            float3 sampleValue = texDiffuseFastHistory_read[samplePosition].rgb;
            firstMoment += sampleValue;
            secondMoment += sampleValue * sampleValue;
        }
    }

    float3 mean = firstMoment * rcp(25.0);
    float3 sigma = sqrt(max(secondMoment * rcp(25.0) - mean * mean, 0.0));
    float3 radius = userSettings.Lighting_FastClampSigma * sigma;

    minimum = min(mean - radius, center);
    maximum = max(mean + radius, center);
}

void SampleHistoryValid(float2 texcoordLast, float3 geo_normal, out float3 diffuseHistory, out float3 fastHistory) {
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

    float3 f00 = texDiffuseFastHistory_read[p00].rgb;
    float3 f10 = texDiffuseFastHistory_read[p10].rgb;
    float3 f01 = texDiffuseFastHistory_read[p01].rgb;
    float3 f11 = texDiffuseFastHistory_read[p11].rgb;

    float3 n00 = octohedral::decode(texNormalHistory_read[p00]);
    float3 n10 = octohedral::decode(texNormalHistory_read[p10]);
    float3 n01 = octohedral::decode(texNormalHistory_read[p01]);
    float3 n11 = octohedral::decode(texNormalHistory_read[p11]);

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
        diffuseHistory = (c00 * w00 + c10 * w10 + c01 * w01 + c11 * w11) / sumWeights;
        fastHistory = (f00 * w00 + f10 * w10 + f01 * w01 + f11 * w11) / sumWeights;
        return;
    }
    
    diffuseHistory = c00;
    fastHistory = f00;
}
