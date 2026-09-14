import aperture;
import settings;
import lib.common;
import lib.bayer;

import lib.sky.transmit;
import lib.sky.multiscatter;
import lib.sky.view;
import lib.exposure;


Texture2D<half3> tex_read;

Texture1D<uint> texHistogram;


[[shader("pixel")]]
float3 main(float2 texcoord: SV_Position) {
    uint2 uv = uint2(texcoord);
    half3 color = tex_read[uv];
    float2 texcoord;

    if (userSettings.Debug_SkyLuts) {
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

    if (userSettings.Debug_Exposure) {
        if (debugWindow(uv, int2(8, 8), int2(256, 32), texcoord)) {
            uint sampleVal = texHistogram.Sample(apt_nearestSampler, texcoord.x);
            color.gb = half2(step(texcoord.y*texcoord.y, sampleVal / float(ap.game.screenSize.x*ap.game.screenSize.y)));
            color.r = 0.0h;

            float meter = saturate(unmix(userSettings.Exposure_Min, userSettings.Exposure_Max, log2(exposure[0].average)));
            if (abs(texcoord.x - meter) < (4.0/ap.game.screenSize.x))
                color.r = 1.0h - color.r;

            // float shit2 = saturate(unmix(settings.Exposure_Min, settings.Exposure_Max, log2(Scene_AvgExposure) + Post_ExposureOffset));
            // if (abs(previewCoord.x - shit2) < 0.008)
            //     color.b = 1.0 - color.b;
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
