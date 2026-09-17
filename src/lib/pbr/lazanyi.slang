public module lazanyi;

import lib.common;


struct LazanyiF {
    float3 f0;
    float3 f82;

    
    __init(float3 f0, float3 f82) {
        this.f0 = f0;
        this.f82 = f82;
    }

    __init(float3 f0) {
        this.f0 = f0;
        this.f82 = LazanyiF.f82_from_f0(f0);
    }

    float A() {
        const float cosThetaMax = acos(1.0 / 7.0);
        const float max5 = pow5(cosThetaMax);

        const float denom = cosThetaMax * pow6(cosThetaMax);
        return saturate((f0.x + (1.0 - f0.x) * max5 - f82.x) / denom);
    }

    float3 F(const in float cosTheta) {
        float cosTheta_inv = saturate(1.0 - cosTheta);
        return saturate(f0 + (1.0 - f0) * pow5(cosTheta_inv) - A() * cosTheta * pow6(cosTheta_inv));
    }

    static float3 f82_from_f0(const in float3 f0) {
        return (2371179624770769.0 * f0 + 2041666790000000.0) / 4412846414770769.0;
    }
};
