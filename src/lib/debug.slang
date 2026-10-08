public module debug;

import aperture;
import lib.text;


// struct DebugWindow {
//     IFunc<float3, float2> onRender;
//     int2 position;
//     int2 size;
//     int[] title;


//     bool getTexcoord(in int2 uv, inout float3 color, out float2 texcoord) {
//         // TODO: how to render title?

//         int2 uv_min = ap.game.screenSize - (position + size);
//         texcoord = float2(uv - uv_min) / size;
//         return all(saturate(texcoord) == texcoord);
//     }

//     void render(in int2 uv, inout float3 color) {
//         float2 texcoord;
//         if (!getTexcoord(uv, color, texcoord)) return;

//         color = onRender(texcoord);
//     }
// }

static const int DebugWindowTitleHeight = 12;

bool renderDebugWindow(const in int2 uv, inout float3 color, int2 uv_pos, int2 uv_size, uint[] title, out float2 texcoord) {
    if (all(clamp(uv, uv_pos, uv_pos + uv_size) == uv)) {
        texcoord = float2(uv - uv_pos + 0.5) / uv_size;
        return true;
    }

    int2 title_min = uv_pos + int2(0, uv_size.y);
    int2 title_max = title_min + int2(uv_size.x, DebugWindowTitleHeight);

    if (all(clamp(uv, title_min, title_max) == uv)) {
        color = 0.2;

        int2 text_pos = title_min + int2(3, DebugWindowTitleHeight - 1);

        beginText(uv, text_pos);
        textData.bgCol = 0.0;
        Print::String(title);
        // Print::Line();
        endText(color);
    }

    // texcoord = 0.0;
    return false;
}

bool renderDebugWindow(const in int2 uv, int2 uv_pos, int2 uv_size, out float2 texcoord) {
    int2 uv_min = ap.game.screenSize - (uv_pos + uv_size);

    texcoord = float2(uv - uv_min) / uv_size;
    return all(saturate(texcoord) == texcoord);
}
