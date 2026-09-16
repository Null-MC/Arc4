import aperture;
import settings;
import lib.common;

extern static const float TAA_RejectionStrength = 0.1;
extern static const int TAA_MaxAccumFrames = 8;
static const uint groupResX = 16;
static const uint groupResY = 16;

static const uint sharedBufferResX = groupResX+2;
static const uint sharedBufferResY = groupResY+2;
static const uint sharedBufferSize = sharedBufferResX*sharedBufferResY;
groupshared float3 sharedBuffer[sharedBufferSize];

[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texMain_write;

Texture2D<float3> texMain_read;

[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texTaaHistory_write;

Texture2D<float4> texTaaHistory_read;


uint2 getSharedUV(const in uint z) {
    return uint2(
        z % sharedBufferResX,
        uint(z / float(sharedBufferResX))
    );
}

int getSharedIndex(const in int2 uv) {
    return uv.y * sharedBufferResX + uv.x;
}

float3 reproject(float3 clipPos) {
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float3 localPosLast = localPos + (ap.camera.position - ap.temporal.position);
    float3 viewPosLast = mul3(ap.temporal.view, localPosLast);
    return mul_project(ap.temporal.projection, viewPosLast);
}

static const int2 sample_offsets[] = {
    int2(-1,-1),
    int2( 0,-1),
    int2( 1,-1),
    int2(-1, 0),
    int2( 1, 0),
    int2(-1, 1),
    int2( 0, 1),
    int2( 1, 1),
};

struct ComputeInput {
    uint groupIndex : SV_GroupIndex;
    uint2 groupPos : SV_GroupID;
    uint2 localPos : SV_GroupThreadID;
    uint2 globalPos : SV_DispatchThreadID;
};

[[shader("compute")]]
[numthreads(groupResX, groupResY)]
void main(ComputeInput input) {
    uint i_base = input.groupIndex * 2u;

    if (i_base < sharedBufferSize) {
        uint2 uv_base = input.groupPos * int2(groupResX, groupResY) - 1u;

        [ForceUnroll]
        for (uint i = 0u; i < 2u; i++) {
            uint i_shared = i_base + i;

            if (i_shared < sharedBufferSize) {
                int2 uv_i = getSharedUV(i_shared);
                sharedBuffer[i_shared] = texMain_read[uv_base + uv_i];
            }
        }
    }

    GroupMemoryBarrierWithGroupSync();

    if (all(input.globalPos < ap.game.screenSize)) {
        float2 texcoord = (input.globalPos + 0.5) / ap.game.screenSize;
        float depth = ap.depth[input.globalPos];

        float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
        float3 clipPosLast = reproject(clipPos);
        float2 uv_prev = clipPosLast.xy * 0.5 + 0.5;

        float4 lastColor = texTaaHistory_read.Sample(apt_linearSampler, uv_prev);

        float mixRate = TAA_MaxAccumFrames;//clamp(lastColor.a, 0.0, TAA_MaxAccumFrames);
        if (userSettings.Accumulation) {
            mixRate = clamp(lastColor.a, 0.0, 666.0);
            if (!all(ap.camera.position == ap.temporal.position) || !all(ap.camera.viewInv[2].xyz == ap.temporal.viewInv[2].xyz)) mixRate = 0.0;
        }
        if (!all(saturate(uv_prev) == uv_prev)) mixRate = 0.0;

        int2 luv = input.localPos + 1;
        float3 in0 = sharedBuffer[getSharedIndex(luv)];

        float3 color_min = in0;
        float3 color_max = in0;

        for (int i = 0; i < 8; i++) {
            float3 in1 = sharedBuffer[getSharedIndex(luv + sample_offsets[i])];

            color_min = min(color_min, in1);
            color_max = max(color_max, in1);
        }

        float3 colorFinal = lerp(lastColor.rgb, in0, 1.0 / ++mixRate);

        if (ap.timing.frameCounter == 0) colorFinal = in0;
        
        if (!userSettings.Accumulation)
            colorFinal = clamp(colorFinal, color_min, color_max);

        texTaaHistory_write[input.globalPos.xy] = float4(colorFinal, mixRate);

        colorFinal = clamp(colorFinal, 0.0, half.maxValue);
        
        texMain_write[input.globalPos.xy] = colorFinal;
    }
}
