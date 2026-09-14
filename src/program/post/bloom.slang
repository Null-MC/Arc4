import aperture;
import settings;
import lib.common;

extern static const int mip_read;
extern static const int mip_write;
extern static const int tile_index;

Texture2D<float3> tex_write;
Texture2D<float3> tex_read;


[[shader("fragment")]]
float3 bloomDown(float2 fragPos : SV_Position) : SV_Target0 {
    uint3 src_size;
    tex_read.GetDimensions(mip_read, src_size.x, src_size.y, src_size.z);
    float2 uv = 2.0 * (fragPos / src_size.xy);

    float3 a = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(-2, +2));
    float3 b = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2( 0, +2));
    float3 c = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(+2, +2));

    float3 d = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(-2, 0));
    float3 e = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2( 0, 0));
    float3 f = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(+2, 0));

    float3 g = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(-2, -2));
    float3 h = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2( 0, -2));
    float3 i = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(+2, -2));

    float3 j = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(-1, +1));
    float3 k = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(+1, +1));
    float3 l = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(-1, -1));
    float3 m = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(+1, -1));

    float3 color =  e  * 0.12500;
    color += (a+c+g+i) * 0.03125;
    color += (b+d+f+h) * 0.06250;
    color += (j+k+l+m) * 0.12500;

    color = clamp(color, 0.0, 65000.0);
    return color;
}


[[shader("fragment")]]
float3 bloomUp(float2 fragPos : SV_Position) : SV_Target0 {
    uint3 src_size;
    tex_read.GetDimensions(mip_read, src_size.x, src_size.y, src_size.z);
    float2 uv = (0.5 * fragPos) / src_size.xy;

    float3 a = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(-1, +1));
    float3 b = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2( 0, +1));
    float3 c = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(+1, +1));

    float3 d = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(-1,  0));
    float3 e = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2( 0,  0));
    float3 f = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(+1,  0));

    float3 g = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(-1, -1));
    float3 h = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2( 0, -1));
    float3 i = tex_read.SampleLevel(apt_linearSampler, uv, mip_read, int2(+1, -1));

    float3 color =   e * 0.2500;
    color += (b+d+f+h) * 0.1250;
    color += (a+c+g+i) * 0.0625;

    if (tile_index == 0) {
        color *= userSettings.Bloom_Strength * 0.01;
    }

    // replacement for no HW additive blending
    color += tex_write.Load(int3(int2(fragPos), mip_write));

    color = clamp(color, 0.0, 65000.0);
    return color;
}
