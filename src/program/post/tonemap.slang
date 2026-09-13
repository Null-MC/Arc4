import aperture;
import lib.exposure;


[[vk::image_format("rgba16f")]]
RWTexture2D<half3> tex_write;

Texture2D<half3> tex_read;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    half3 color = tex_read[globalPos];

    color /= half(exposure[0].average);

    color = half3(aces_fit_tonemap(color));

    tex_write[globalPos] = color;
}

float3 aces_fit_tonemap(const in float3 x) {
    const float a = 2.51f;
    const float b = 0.03f;
    const float c = 2.43f;
    const float d = 0.59f;
    const float e = 0.14f;
    
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}
