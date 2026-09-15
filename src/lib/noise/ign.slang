public module IGN;

import aperture;
import lib.common;

namespace IGN {

    static const float3 IGN_magic = float3(0.06711056, 0.00583715, 52.9829189);


    float get(const in float2 pixel) {
        float x = dot(pixel, IGN_magic.xy);
        return fract(IGN_magic.z * fract(x));
    }

    float getAnimated(const in float2 pixel, const in float time) {
        float2 uv = pixel + time * 5.588238;
        return fract(IGN_magic.z * fract(dot(IGN_magic.xy, uv)));
    }

    float getAnimated(const in float2 pixel) {
        return getAnimated(pixel, ap.timing.frameCounter);
    }

}
