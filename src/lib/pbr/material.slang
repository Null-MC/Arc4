public module material;

import lib.common;


float mat_f0(const in float specular_g) {
    return specular_g > 0.0 ? specular_g : 0.04;
}

float mat_emission(const in float specular_a) {
    float emission = fract(specular_a);
    return pow2(emission) * 700.0;
}

float mat_sss_lab(const in half specular_b) {
    return max(specular_b - (64.0/255.0), 0.0) * (255.0/191.0);
}
