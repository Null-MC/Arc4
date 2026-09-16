import aperture;
import lib.common;

extern static const uint BLOOM_INDEX;
extern static const uint MIP_INDEX;

groupshared half3 sharedCenter[17*17];
groupshared half3 sharedNeighbor[18*18];

[[vk::image_format("rgba16f")]]
RWTexture2D<half3> tex_write;

Texture2D<half3> tex_read;

int getSharedCenterIndex(const in int2 uv) {
    return uv.y * 17 + uv.x;
}

int getSharedNeighborIndex(const in int2 uv) {
    return uv.y * 18 + uv.x;
}

void copyToSharedCenter(const in float2 uv_base, const in uint i_shared) {
    if (i_shared >= (17*17)) return;

    float2 uv = uv_base + 2 * int2(i_shared % 17, i_shared / 17);

    // float2 texcoord = uv / viewSize;

    sharedCenter[i_shared] = tex_read[uv];
}

void copyToSharedNeighbor(const in float2 uv_base, const in uint i_shared) {
    if (i_shared >= (18*18)) return;

    float2 uv = uv_base + 2*int2(i_shared % 18, i_shared / 18) + 1;

    float2 texcoord = uv / viewSize;
    // TODO: apply clamping!
    sharedNeighbor[i_shared] = texture(TEX_SOURCE, texcoord).rgb;
}


struct ComputeInput {
    uint groupIndex : SV_GroupIndex;
    uint2 groupPos : SV_GroupID;
    uint2 globalPos : SV_DispatchThreadID;
    uint2 localPos : SV_GroupThreadID;
};

[[shader("compute")]]
[numthreads(16,16)]
void bloomDown(ComputeInput input) {
    // preload shared memory
    int i_center = input.groupIndex * 2;
    float2 uv_center = input.groupPos * 32.0 - 0.5;

    copyToSharedCenter(uv_center, i_center + 0);
    copyToSharedCenter(uv_center, i_center + 1);

    int i_neighbor = input.groupIndex * 2;
    float2 uv_neighbor = src_pos + gl_WorkGroupID.xy * 32.0 - 1.5;

    copyToSharedNeighbor(uv_neighbor, i_neighbor + 0);
    copyToSharedNeighbor(uv_neighbor, i_neighbor + 1);

    GroupMemoryBarrier();

    // exit early if OOB
    int2 local_uv = int2(globalPos);
    int2 outputSize = int2(ceil(viewSize / exp2(BLOOM_INDEX+1)));
    if (any(local_uv >= outputSize)) return;

    int2 neightbor_local_uv = input.localPos + 1;

    half3 a = sharedNeighbor[getSharedNeighborIndex(neightbor_local_uv + int2(-1, +1))];
    half3 b = sharedNeighbor[getSharedNeighborIndex(neightbor_local_uv + int2( 0, +1))];
    half3 c = sharedNeighbor[getSharedNeighborIndex(neightbor_local_uv + int2(+1, +1))];

    half3 d = sharedNeighbor[getSharedNeighborIndex(neightbor_local_uv + int2(-1,  0))];
    half3 e = sharedNeighbor[getSharedNeighborIndex(neightbor_local_uv + int2( 0,  0))];
    half3 f = sharedNeighbor[getSharedNeighborIndex(neightbor_local_uv + int2(+1,  0))];

    half3 g = sharedNeighbor[getSharedNeighborIndex(neightbor_local_uv + int2(-1, -1))];
    half3 h = sharedNeighbor[getSharedNeighborIndex(neightbor_local_uv + int2( 0, -1))];
    half3 i = sharedNeighbor[getSharedNeighborIndex(neightbor_local_uv + int2(+1, -1))];

    int2 center_local_uv = input.localPos;

    half3 j = sharedCenter[getSharedCenterIndex(center_local_uv + int2(0, 1))];
    half3 k = sharedCenter[getSharedCenterIndex(center_local_uv + int2(1, 1))];
    half3 l = sharedCenter[getSharedCenterIndex(center_local_uv + int2(0, 0))];
    half3 m = sharedCenter[getSharedCenterIndex(center_local_uv + int2(1, 0))];

    half3 color;
    color = e*0.125h;
    color += (a+c+g+i)*0.03125h;
    color += (b+d+f+h)*0.0625h;
    color += (j+k+l+m)*0.125h;

    // vec2 outputPos = GetBloomTileInnerPosition(BLOOM_TILE);
    ivec2 output_uv = local_uv + ivec2(outputPos * viewSize + EPSILON);
    tex_write[input.globalPos][mip] = color;
}


[[shader("fragment")]]
half3 applyBloomUp(float2 pos : SV_Position) : SV_Target0 {
    uint3 texSrc_size;
    texBloom.GetDimensions(MIP_INDEX, texSrc_size.x, texSrc_size.y, texSrc_size.z);
    float2 srcPixelSize = rcp(texSrc_size.xy);

    float2 uv = 0.5 * pos * srcPixelSize;

    half3 a = texBloom.SampleLevel(uv, MIP_INDEX, int2(-1, +1));
    half3 b = texBloom.SampleLevel(uv, MIP_INDEX, int2( 0, +1));
    half3 c = texBloom.SampleLevel(uv, MIP_INDEX, int2(+1, +1));

    half3 d = texBloom.SampleLevel(uv, MIP_INDEX, int2(-1,  0));
    half3 e = texBloom.SampleLevel(uv, MIP_INDEX, int2( 0,  0));
    half3 f = texBloom.SampleLevel(uv, MIP_INDEX, int2(+1,  0));

    half3 g = texBloom.SampleLevel(uv, MIP_INDEX, int2(-1, -1));
    half3 h = texBloom.SampleLevel(uv, MIP_INDEX, int2( 0, -1));
    half3 i = texBloom.SampleLevel(uv, MIP_INDEX, int2(+1, -1));

    float3 color =   e * 0.2500;
    color += (b+d+f+h) * 0.1250;
    color += (a+c+g+i) * 0.0625;

    if (BLOOM_INDEX == 0u) {
        color = fma(color, settings.Bloom_Strength, texSource[int2(pos)]);
    }

    color = clamp(color, 0.0, half.maxValue);
    return half3(color);
}
