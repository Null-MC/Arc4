public module bicubic;


float w0(float a) {
    return (1.0/6.0)*(a*(a*(-a + 3.0) - 3.0) + 1.0);
}

float w1(float a) {
    return (1.0/6.0)*(a*a*(3.0*a - 6.0) + 4.0);
}

float w2(float a) {
    return (1.0/6.0)*(a*(a*(-3.0*a + 3.0) + 3.0) + 1.0);
}

float w3(float a) {
    return (1.0/6.0)*(a*a*a);
}

float g0(float a) {
    return w0(a) + w1(a);
}

float g1(float a) {
    return w2(a) + w3(a);
}

float h0(float a) {
    return -1.0 + w1(a) / (w0(a) + w1(a));
}

float h1(float a) {
    return 1.0 + w3(a) / (w2(a) + w3(a));
}

extension Texture2D {
    float4 SampleBicubic(SamplerState sampler, float2 texcoord) {
        int3 size;
        this.GetDimensions(0u, size.x, size.y, size.z);

        // float4 texelSize = float4(size.xy, 1.0 / size.xy);
        float2 uv = texcoord * size.xy;

        float2 iuv = floor(uv);
        float2 fuv = fract(uv);

        float g0x = g0(fuv.x);
        float g1x = g1(fuv.x);
        float h0x = h0(fuv.x);
        float h1x = h1(fuv.x);
        float h0y = h0(fuv.y);
        float h1y = h1(fuv.y);

        float2 p0 = (float2(iuv.x + h0x, iuv.y + h0y) - 0.5) / size.xy;
        float2 p1 = (float2(iuv.x + h1x, iuv.y + h0y) - 0.5) / size.xy;
        float2 p2 = (float2(iuv.x + h0x, iuv.y + h1y) - 0.5) / size.xy;
        float2 p3 = (float2(iuv.x + h1x, iuv.y + h1y) - 0.5) / size.xy;

        return g0(fuv.y) * (g0x * Sample(sampler, p0)  +
                            g1x * Sample(sampler, p1)) +
            g1(fuv.y) * (g0x * Sample(sampler, p2)  +
                            g1x * Sample(sampler, p3));
    }
}
