public module HCM;

import lib.pbr.lazanyi;

// https://helpx.adobe.com/substance-3d-general/adobe-standard-material/metal-material-references.html


static const LazanyiF lazanyi_hcm[8] = LazanyiF[](
    LazanyiF( // iron
        half3(0.953h, 0.945h, 0.914h),
        half3(0.933h, 0.945h, 0.953h)),

    LazanyiF( // gold
        half3(1.000h, 0.859h, 0.596h),
        half3(0.973h, 0.984h, 0.961h)),

    LazanyiF( // aluminum
        half3(0.961h, 0.965h, 0.965h),
        half3(0.961h, 0.973h, 0.980h)),

    LazanyiF( // chrome
        half3(0.769h, 0.773h, 0.769h),
        half3(0.875h, 0.882h, 0.914h)),

    LazanyiF( // copper
        half3(1.000h, 0.827h, 0.753h),
        half3(0.988h, 0.972h, 0.969h)),

    LazanyiF( // lead
        half3(0.790h, 0.870h, 0.850h),
        half3(0.830h, 0.800h, 0.830h)),

    LazanyiF( // platinum
        half3(0.980h, 0.969h, 0.918h),
        half3(0.976h, 0.976h, 0.973h)),

    LazanyiF( // silver
        half3(0.996h, 0.992h, 0.984h),
        half3(0.996h, 1.000h, 1.000h))
);
