import aperture;
import settings;
import lib.bayer;
import lib.sky.transmit;
import lib.sky.multiscatter;
import lib.sky.view;


Texture2D<half3> tex_read;


[[shader("pixel")]]
float3 main(float2 texcoord: SV_Position) {
    uint2 uv = uint2(texcoord);
    half3 color = tex_read[uv];

    if (userSettings.Debug_SkyLuts) {
        float2 texcoord;
        if (debugWindow(uv, int2(8, 8), int2(512, 128), texcoord)) {
            color = HillaireSky::sampleTransmit(texcoord);
        }
        if (debugWindow(uv, int2(8, 144), int2(128, 128), texcoord)) {
            color = HillaireSky::sampleMultiScatter(texcoord) * 0.008h;
        }
        if (debugWindow(uv, int2(144, 144), int2(128, 128), texcoord)) {
            color = HillaireSky::sampleView(texcoord) * 0.008h;
        }
    }

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
