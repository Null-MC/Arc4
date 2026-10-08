public module light_data;

import aperture;
import settings;


half4 getLightColorRange(const in int blockId) {
    if (blockId < 1 || blockId >= 255) return half4(1.0h, 1.0h, 1.0h, 0.0h);

    int data = LightDataBuffer.list[blockId-1];
    half4 color = unpackUnorm4x8ToHalf(data);
    color.a *= 255.0h;
    return color;
}

half4 getLightColorRange(const in BlockData block) {
    half4 data = getLightColorRange(block.customId);
    if (data.a < 1e-6h) data.a = half(block.emission);
    return data;
}
