import aperture;
import settings;
import lib.common;
import lib.color_transformer;
import lib.noise.bayer;
import lib.text;

import lib.sky.transmit;
import lib.sky.multiscatter;
import lib.sky.view;
import lib.exposure;
import lib.octohedral;
import lib.light.list;


extern static const bool DebugDefer = false;
extern static const bool Debug_Lighting = false;
extern static const bool Debug_LightList = false;

Texture2D<float3> tex_read;

Texture2D<float3> texBloom;
Texture1D<uint> texHistogram;
Texture2D<half3> texDeferColor;
Texture2D<half4> texDeferNormal;
Texture2D<half4> texDeferSpecular;
Texture2D<half2> texDeferData;
Texture2D<half3> texDiffuseHistory_write;


[[shader("pixel")]]
float3 main(float2 fragPos: SV_Position) {
    uint2 uv = uint2(fragPos);
    float3 color = tex_read[uv];
    float2 texcoord;

    if (DebugDefer) {
        // Geometry Normal
        if (debugWindow(uv, int2(8, 8), int2(320, 240), texcoord)) {
            half2 geoNormalData = texDeferNormal.SampleLevel(apt_nearestSampler, texcoord, 0.0).xy;
            color = octohedral::decode(geoNormalData) * 0.5 + 0.5;
        }
        // Texture Normal
        if (debugWindow(uv, int2(8, 256), int2(320, 240), texcoord)) {
            half2 geoNormalData = texDeferNormal.SampleLevel(apt_nearestSampler, texcoord, 0.0).zw;
            color = octohedral::decode(geoNormalData) * 0.5 + 0.5;
        }
        // Albedo Color
        if (debugWindow(uv, int2(336, 8), int2(320, 240), texcoord)) {
            color = texDeferColor.SampleLevel(apt_nearestSampler, texcoord, 0.0);
        }
        // Data
        if (debugWindow(uv, int2(336, 256), int2(320, 240), texcoord)) {
            color = 0.1 * asfloat(texDeferData.SampleLevel(apt_nearestSampler, texcoord, 0.0).g);
        }
        // Specular smoothness, f0, emission
        if (debugWindow(uv, int2(672, 8), int2(320, 240), texcoord)) {
            color = texDeferSpecular.SampleLevel(apt_nearestSampler, texcoord, 0.0).rga;
        }
    }

    if (userSettings.Debug_SkyLuts) {
        if (debugWindow(uv, int2(8, 8), int2(512, 128), texcoord)) {
            color = HillaireSky::sampleTransmit(texcoord);
        }
        if (debugWindow(uv, int2(8, 144), int2(128, 128), texcoord)) {
            color = HillaireSky::sampleMultiScatter(texcoord) * 0.008;
        }
        if (debugWindow(uv, int2(144, 144), int2(128, 128), texcoord)) {
            color = HillaireSky::sampleView(texcoord) * 0.008;
        }
    }

    if (Debug_Lighting) {
        if (debugWindow(uv, int2(8, 8), int2(320, 240), texcoord)) {
            color = texDiffuseHistory_write.SampleLevel(apt_nearestSampler, texcoord, 0.0);
        }
    }

    if (userSettings.Debug_Exposure) {
        if (debugWindow(uv, int2(8, 8), int2(256, 32), texcoord)) {
            uint sampleVal = texHistogram.Sample(apt_nearestSampler, texcoord.x);
            color.gb = step(texcoord.y*texcoord.y, sampleVal / float(ap.game.screenSize.x*ap.game.screenSize.y));
            color.r = 0.0;

            float meter = saturate(unmix(userSettings.Exposure_Min, userSettings.Exposure_Max, log2(exposure[0].average)));
            if (abs(texcoord.x - meter) < (4.0/ap.game.screenSize.x))
                color.r = 1.0 - color.r;
        }
    }

    color = linearToSrgb(color);

    if (Debug_LightList) {
        beginText(int2(fragPos*0.5), int2(4, ap.game.screenSize.y/2 - 32));
        Print::String(uint[](_G, _l, _o, _b, _a, _l, _colon, _space));
        Print::UnsignedInt(LightListCounters[0].global.load());
        Print::Line();
        Print::String(uint[](_L, _o, _c, _a, _l, _colon, _space));
        Print::UnsignedInt(LightListCounters[0].local.load());
        Print::Line();
        endText(color);
    }

    const float ditherScale = rcp(255.0);
    color += (GetBayerValue(uv) - 0.5) * ditherScale;

    return color;
}

bool debugWindow(const in int2 uv, int2 uv_pos, int2 uv_size, out float2 texcoord) {
    int2 uv_min = ap.game.screenSize - (uv_pos + uv_size);

    texcoord = float2(uv - uv_min) / uv_size;
    return all(saturate(texcoord) == texcoord);
}
