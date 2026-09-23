public module ACES;

import color_transformer;


namespace ACES {

    static const float CINEMA_WHITE = 48;
    static const float CINEMA_BLACK = CINEMA_WHITE / 2400.0;
    static const float DIM_SURROUND_GAMMA = 0.9811;

    static const float RRT_SAT_FACTOR = 0.96;
    static const float ODT_SAT_FACTOR = 0.93;

    static const float3 AP1_RGB2Y = float3(0.272229, 0.674082, 0.0536895);

    static const float3x3 D60_2_D65_CAT = float3x3(
        0.98722400, -0.00611327, 0.0159533,
        -0.00759836,  1.00186000, 0.0053302,
        0.00307257, -0.00509595, 1.0816800
    );

    // static const float3x3 AP0_2_AP1_MAT = {
    //      1.4514393161, -0.2365107469, -0.2149285693,
    //     -0.0765537734,  1.1762296998, -0.0996759264,
    //      0.0083161484, -0.0060324498,  0.9977163014
    // };

    // static const float3x3 AP1_2_sRGB = {
    //     1.70505, -0.62179, -0.08326,
    //     -0.13026, 1.14080, -0.01055,
    //     -0.02400, -0.12897, 1.15297,
    // };

    // static const float3x3 AP1_2_AP0_MAT = {
    //      0.6954522414, 0.1406786965, 0.1638690622,
    //      0.0447945634, 0.8596711185, 0.0955343182,
    //     -0.0055258826, 0.0040252103, 1.0015006723
    // };
    static const float3x3 AP1_2_AP0_MAT = float3x3(
         0.6954522414, 0.1406786965, 0.1638690622,
         0.0447945634, 0.8596711185, 0.0955343182,
        -0.0055258826, 0.0040252103, 1.0015006723
    );

    static const float3x3 sRGB_2_AP0 = float3x3(
        0.4397010, 0.3829780, 0.1773350,
        0.0897923, 0.8134230, 0.0967616,
        0.0175440, 0.1115440, 0.8707040
    );

    static const float3x3 sRGB_to_AP1 = float3x3(
        0.61319, 0.33951, 0.04737,
        0.07021, 0.91634, 0.01345,
        0.02062, 0.10957, 0.86961
    );

    static const float3x3 AP1_to_sRGB = float3x3(
         1.70485868, -0.62171607, -0.08314261,
        -0.13025866,  1.14073577, -0.01047711,
        -0.02400751, -0.12896391,  1.15297142
    );

    static const float3x3 AP1_2_XYZ_MAT = float3x3(
        0.6624541811, 0.1340042065, 0.1561876870,
        0.2722287168, 0.6740817658, 0.0536895174,
        -0.0055746495, 0.0040607335, 1.0103391003
    );

    static const float3x3 XYZ_2_AP1_MAT = float3x3(
        1.6410233797, -0.3248032942, -0.2364246952,
        -0.6636628587,  1.6153315917,  0.0167563477,
        0.0117218943, -0.0082844420,  0.9883948585
    );

    static const float3x3 XYZ_2_REC709_MAT = float3x3(
        3.2409699419, -1.5373831776, -0.4986107603,
        -0.9692436363,  1.8759675015,  0.0415550574,
        0.0556300797, -0.2039769589,  1.0569715142
    );


    float3 Y_2_linCV(float3 Y, float Ymax, float Ymin) {
        return (Y - Ymin) / (Ymax - Ymin);
    }

    float3 XYZ_2_xyY(float3 XYZ) {
        float divisor = max(dot(XYZ, (1.0).xxx), 1e-4);
        return float3(XYZ.xy / divisor, XYZ.y);
    }

    float3 xyY_2_XYZ(float3 xyY) {
        float m = xyY.z / max(xyY.y, 1e-4);
        float3 XYZ = float3(xyY.xz, (1.0 - xyY.x - xyY.y));
        XYZ.xz *= m;
        return XYZ;
    }

    float3 linear_to_cg(const in float3 color) {
        return mul(sRGB_to_AP1, color);
    }

    float cct_from_Linear(float lin) {
        if (lin > 0.0078125)
            return log2(lin) / 17.52 + (9.72/17.52);
        
        return lin * 10.5402377416545 + 0.0729055341958355;
    }

    float3 cct_from_Linear(float3 lin) {
        return float3(
            cct_from_Linear(lin.r),
            cct_from_Linear(lin.g),
            cct_from_Linear(lin.b));
    }

    float Linear_from_cct(float cct) {
        if (cct > 0.155251141552511)
            return exp2(cct * 17.52 - 9.72);
        
        return cct / 10.5402377416545 - (0.0729055341958355/10.5402377416545);
    }

    float3 Linear_from_cct(float3 cct) {
        return float3(
            Linear_from_cct(cct.r),
            Linear_from_cct(cct.g),
            Linear_from_cct(cct.b));
    }

    float3 DarkToDimSurround(float3 linearCV) {
        float3 XYZ = mul(AP1_2_XYZ_MAT, linearCV);

        float3 xyY = XYZ_2_xyY(XYZ);
        xyY.z = clamp(xyY.z, 0.0, half.maxValue);
        xyY.z = pow(xyY.z, DIM_SURROUND_GAMMA);
        XYZ = xyY_2_XYZ(xyY);

        return mul(XYZ_2_AP1_MAT, XYZ);
    }

}

struct ACEScg_Transformer : ColorTransformer {
    public override float3 fromGamma(const in float3 color) {
        return fromLinear(srgbToLinear(color));
    }

    public override float3 fromLinear(const in float3 color) {
        return mul(ACES::sRGB_to_AP1, color);
    }

    public float3 toLinear(const in float3 color) {
        return mul(ACES::AP1_to_sRGB, color);
    }
    
    public override float3 toGamma(const in float3 color) {
        return linearToSrgb(toLinear(color));
    }
}
