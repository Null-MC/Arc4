public module color_transformer;


interface ColorTransformer {
    float3 fromGamma(const in float3 color);

    float3 fromLinear(const in float3 color);

    // TODO: support for color-correction space
    // float3 toCorrection(const in float3 color);
    // float3 fromCorrection(const in float3 color);

    float3 toLinear(const in float3 color);

    float3 toGamma(const in float3 color);
}

struct sRGB_Transformer : ColorTransformer {
    public override float3 fromGamma(const in float3 color) {
        return srgbToLinear(color);
    }

    public override float3 fromLinear(const in float3 color) {
        return color;
    }

    public float3 toLinear(const in float3 color) {
        return color;
    }

    public override float3 toGamma(const in float3 color) {
        return linearToSrgb(color);
    }
}

float3 srgbToLinear(const in float3 color) {
    const float3 cutoff = 0.04045;
    float3 low = color / 12.92;
    float3 high = pow(max(color + 0.055, 0.0) / 1.055, 2.4);
    return lerp(low, high, step(cutoff, color));
}

float3 linearToSrgb(const in float3 color) {
    const float3 cutoff = 0.0031308;
    float3 low = color * 12.92;
    float3 high = 1.055 * pow(max(color, 0.0), 1.0 / 2.4) - 0.055;
    return lerp(low, high, step(cutoff, color));
}
