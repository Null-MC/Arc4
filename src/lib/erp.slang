public module erp;

import aperture;
import lib.common;


namespace ERP {
    
    // static const bool ERP_FOCUS = false;

    float3 fromUV(in float2 uv) {
        uv.y = 1.0 - uv.y;

        // if (ERP_FOCUS) {
        //     uv.y = (uv.y*2.0-1.0);
        //     uv.y = (uv.y*uv.y) * -sign(uv.y);
        //     uv.y = uv.y*0.5 + 0.5;
        // }

        float2 sphereCoord = (uv*float2(2.0, 1.0) - float2(1.0, 0.0)) * PI;

        float2 _sin = sin(sphereCoord);
        float2 _cos = cos(sphereCoord);
        
        return float3(_cos.xy, _sin.x) * float3(_sin.y, 1.0, _sin.y);
    }

    float2 toUV(const in float3 dir) {
        float2 uv = float2(0.5, sign(dir.y));

        if (abs(dir.y) < 0.9999) {
            uv = float2(
                atan2(dir.z, dir.x),
                acos(dir.y)
            ) / PI;

            uv.x = uv.x * 0.5 + 0.5;

            //uv = (uv) + float2(0.5, 0.0);

            // if (ERP_FOCUS) {
            //     uv.y = (uv.y*2.0-1.0);
            //     uv.y = sqrt(abs(uv.y)) * -sign(uv.y);
            //     uv.y = uv.y*0.5 + 0.5;
            // }

            uv.y = 1.0 - uv.y;
        }

        return uv;
    }

}
