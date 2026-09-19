public module common;

import aperture;
import lib.color_transformer;
import lib.aces;


static const float PI = 3.1415926535897932384626433832795;

static const float SamplingBias = -1.0;

static const float3 WaterAbsorb = float3(0.35, 0.07, 0.03);

// static const ColorTransformer transformer = new sRGB_Transformer();
static const ColorTransformer transformer = new ACES_Transformer();


float luminance(const in float3 color) {
    static const float3 L = float3(0.2126, 0.7152, 0.0722);
    return dot(color, L);
}

half3 maxOf(half3 x, half3 y, half3 z) {
    return max(x, max(y, z));
}

half3 minOf(half3 x, half3 y, half3 z) {
    return min(x, min(y, z));
}

float minOf(float3 vec) {
    return min(vec.x, min(vec.y, vec.z));
}

T sumOf<T>(const in vector<T, 2> vec) where T: IArithmetic {
    return vec.x + vec.y;
}

T sumOf<T>(const in vector<T, 3> vec) where T: IArithmetic {
    return vec.x + vec.y + vec.z;
}

T pow2<T>(const in T value) where T: IArithmetic {
    return value * value;
}

T pow3<T>(const in T value) where T: IArithmetic {
    return value * value * value;
}

T pow5<T>(const in T value) where T: IArithmetic {
    T value_2 = pow2(value);
    return value_2 * value_2 * value;
}

T pow4<T>(const in T value) where T: IArithmetic {
    T value_2 = pow2(value);
    return value_2 * value_2;
}

T pow6<T>(const in T value) where T: IArithmetic {
    T value_2 = pow2(value);
    return value_2 * value_2 * value_2;
}

T unmix<T>(const in T valueMin, const in T valueMax, const in T value) where T: IFloat {
    return (value - valueMin) / (valueMax - valueMin);
}

float3 mul3(const in float4x4 matrix, const in float3 vector) {
    return mul(matrix, float4(vector, 1.0)).xyz;
}

float3 mul_project(const in float4x4 matrix, const in float3 vector) {
    float4 result = mul(matrix, float4(vector, 1.0));
    return result.xyz / result.w;
}

float lengthSq(float3 vec) {
    return dot(vec, vec);
}
