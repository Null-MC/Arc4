public module material;

import settings;
import lib.common;


// #if MATERIAL_FORMAT == 2
// static const ISpecularReader SpecularReader = getSpecularReader();
// #else
// static const ISpecularReader SpecularReader = getSpecularReader();
// #endif

static ISpecularReader getSpecularReader() {
    switch (userSettings.Material_Format) {
        case MaterialFormats.LabPbr:
            return LabPbr();
        case MaterialFormats.OldPbr:
            return OldPbr();
        default:
            return DefaultPbr();
    }
}


float mat_emission(const in half4 specularMap) {
    float emission = getSpecularReader().emission(specularMap);
    return emission * 200.0;
}


interface ISpecularReader {
    float roughness(const in half4 specularMap);
    float f0(const in half4 specularMap);
    int hcm(const in half4 specularMap);
    float metalness(const in half4 specularMap);
    float emission(const in half4 specularMap);
    float porosity(const in half4 specularMap);
    float sss(const in half4 specularMap);
}

struct LabPbr : ISpecularReader {
    float roughness(const in half4 specularMap) {
        return pow2(1.0 - specularMap.r);
    }

    float metalness(const in half4 specularMap) {
        return step(0.9, f0(specularMap));
    }

    float f0(const in half4 specularMap) {
        return specularMap.g > 0.0 ? specularMap.g : 0.04;
    }

    int hcm(const in half4 specularMap) {
        return int(floor(specularMap.g * 255.0 - 229.5));
    }

    float emission(const in half4 specularMap) {
        return fract(specularMap.a);
    }

    float porosity(const in half4 specularMap) {
        return specularMap.b * (255.0/64.0) * step(specularMap.b, (64.5/255.0));
    }

    float sss(const in half4 specularMap) {
        return max(specularMap.b - (64.0/255.0), 0.0) * (255.0/191.0);
    }
};

struct OldPbr : ISpecularReader {
    float roughness(const in half4 specularMap) {
        return pow2(1.0 - specularMap.r);
    }
    
    float f0(const in half4 specularMap) {
        // TODO: change if metal?
        return 0.04;
    }

    int hcm(const in half4 specularMap) {
        return 0;
    }

    float metalness(const in half4 specularMap) {
        return specularMap.g;
    }

    float emission(const in half4 specularMap) {
        return specularMap.b;
    }

    float porosity(const in half4 specularMap) {
        return 0.0;
    }

    float sss(const in half4 specularMap) {
        return 0.0;
    }
};

struct DefaultPbr : ISpecularReader {
    float roughness(const in half4 specularMap) {
        return 0.92;
    }
    
    float f0(const in half4 specularMap) {
        return 0.04;
    }

    int hcm(const in half4 specularMap) {
        return 0;
    }

    float metalness(const in half4 specularMap) {
        return 0.0;
    }

    float emission(const in half4 specularMap) {
        return 0.0;
    }

    float porosity(const in half4 specularMap) {
        return 0.0;
    }

    float sss(const in half4 specularMap) {
        return 0.0;
    }
};
