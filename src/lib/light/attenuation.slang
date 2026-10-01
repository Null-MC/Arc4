public module attenuation;

import lib.common;


namespace Attenuation {

    public float getLinear(const in float lightDist, const in float lightRange) {
        float linear = max(1.0 - lightDist / lightRange, 0.0);
        return pow(linear, 1.0 + lightRange);
    }

    public float getExponential(const in float lightDist) {
        return rcp(1.0 + pow2(lightDist*0.5));
    }

}
