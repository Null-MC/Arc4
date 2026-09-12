public module R2;

// https://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/

namespace R2 {

    public float D1(const in float seed) {
        const float G = 1.6180339887498948482;
        const float INV = rcp(G);

        return frac(INV * seed + 0.5);
    }

    public float2 D2(const in float seed) {
        const float G = 1.32471795724474602596;
        const float2 INV2 = rcp(float2(G, G*G));

        return frac(INV2 * seed + 0.5);
    }

}
