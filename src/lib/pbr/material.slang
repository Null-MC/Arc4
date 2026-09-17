public module material;

import lib.common;


float mat_emission(const in float specular_a) {
    float emission = fract(specular_a);
    return pow2(emission) * 700.0;
}
