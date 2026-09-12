import aperture;
import lib.bayer;

import lib.sky.transmit;
import lib.sky.multiscatter;
import lib.sky.view;


Texture2D<half3> tex_read;


[[shader("pixel")]]
float3 main(float2 texcoord: SV_Position) {
    uint2 uv = uint2(texcoord);
    half3 color = tex_read[uv];

    // float2 texcoord;
    // if (debugWindow(uv, int2(8, 8), int2(256, 64), texcoord)) {
    //     color = HillaireSky::sampleTransmit(texcoord);
    // }
    // if (debugWindow(uv, int2(272, 8), int2(64, 64), texcoord)) {
    //     color = HillaireSky::sampleMultiScatter(texcoord) * 0.008h;
    // }
    // if (debugWindow(uv, int2(352, 8), int2(64, 64), texcoord)) {
    //     color = HillaireSky::sampleView(texcoord) * 0.008h;
    // }

    color = pow(color, half3(1.0/2.2));

    const half ditherScale = rcp(255.0h);
    color += half3(GetBayerValue(uv) * ditherScale);

    return color;
}

bool debugWindow(const in int2 uv, int2 uv_pos, int2 uv_size, out float2 texcoord) {
    int2 uv_min = ap.game.screenSize - (uv_pos + uv_size);

    texcoord = float2(uv - uv_min) / uv_size;
    return all(saturate(texcoord) == texcoord);
}
