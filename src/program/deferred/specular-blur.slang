import aperture;
import settings;
import lib.common;
import lib.octohedral;
import lib.pbr.material;
import lib.atrous;


extern static const int ATrousLevel;

static const int ATrous_StepWidth = (1 << ATrousLevel);

[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texSpecular_write;

Texture2D<float4> texSpecular_read;

Texture2D<half4> texDeferNormal;
Texture2D<half4> texDeferSpecular;


float atrous_GetRoughness(const in int2 uv) {
    half4 specularMap = texDeferSpecular[uv];
    return getSpecularReader().roughness(specularMap);
}

float3 atrous_GetTexNormal(const in int2 uv) {
    return octohedral::decode(texDeferNormal[uv].zw);
}

float3 atrous_GetViewPosition(const in uint2 uv) {
    float depth = ap.depth[uv];
    float2 texcoord = (uv + 0.5) / ap.game.renderSize;
    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    return mul_project(ap.camera.projectionInv, clipPos);
}

float3 filter_ATrous(const in float2 texcoord) {
    int2 uv = int2(texcoord * ap.game.screenSize);

    // float3 center_color = texSpecular_read[uv].rgb;
    float3 center_texNormal = atrous_GetTexNormal(uv);
    float3 center_viewPos = atrous_GetViewPosition(uv);
    float center_roughness = atrous_GetRoughness(uv);

    const float c_phi = 0.1;
    const float n_phi = 0.1;
    const float p_phi = 0.1;
    const float r_phi = 0.1;

    float total_weight = 0.0;
    float3 sum = 0.0;

    [ForceUnroll]
    for (int i = 0; i < 25; i++) {
        int2 sample_uv = atrousOffsets[i] * ATrous_StepWidth + uv;

        float dist2;
        float3 t;

        float3 ctmp = texSpecular_read[sample_uv].rgb;
        // float3 t = center_color - ctmp;
        // float dist2 = dot(t,t);
        // float c_w = 1.0;//min(exp(-(dist2)/c_phi), 1.0);

        float3 ntmp = atrous_GetTexNormal(sample_uv);
        t = center_texNormal - ntmp;
        // dist2 = max(dot(t,t)/(stepwidth*stepwidth),0.0);
        dist2 = max(dot(t, t), 0.0);
        float n_w = min(exp(-(dist2)/n_phi), 1.0);

        float3 ptmp = atrous_GetViewPosition(sample_uv);
        t = center_viewPos - ptmp;
        dist2 = dot(t, t);
        float p_w = min(exp(-(dist2)/p_phi), 1.0);

        float rtmp = atrous_GetRoughness(sample_uv);
        // t.r = center_roughness - rtmp;
        // dist2 = t.r*t.r; //max(t, 0.0);
        // float r_w = min(exp(-(dist2)/r_phi), 1.0);
        float r_w = abs(center_roughness - rtmp) < 0.02 ? 1.0 : 0.0;
        
        // float kernel_weight = c_w * n_w * p_w * atrousKernel[i];
        float kernel_weight = r_w * n_w * p_w * atrousKernel[i];
        sum += ctmp * kernel_weight;
        total_weight += kernel_weight;
    }

    return sum / max(total_weight, 1e-6);
}


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float depth = ap.depth[globalPos];
    float4 specular = 0.0;
    
    if (depth > 0.0) {
        float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
        if (userSettings.TAA_Enabled) texcoord -= scene.TAA_jitter;

        specular.rgb = filter_ATrous(texcoord);
    }

    specular.rgb = clamp(specular.rgb, 0.0, half.maxValue);
    texSpecular_write[globalPos] = specular;
}
