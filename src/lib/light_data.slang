public module light_data;

import settings;


half4 getLightColorRange(const in int blockId) {
    if (blockId < 1 || blockId >= 255) return 0.0h;

    int data = LightDataBuffer.list[blockId-1];
    half4 color = unpackUnorm4x8ToHalf(data);
    color.a *= 255.0h;
    return color;
}
