import aperture;
import settings;
import lib.common;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.multiscatter;
import lib.noise.hash;
import lib.shadows;
import lib.froxel;


extern static const int Froxel_MaxFrames = 15;
extern static const uint Froxel_SkyLight_StepCount = 8;

[[vk::image_format("rgba16f")]]
RWTexture3D<half4> texFroxel_write;

Texture3D<half4> texFroxel_read;
SamplerState froxelSampler;


struct ComputeInput {
    uint groupIndex : SV_GroupIndex;
    uint3 groupPos : SV_GroupID;
    uint3 localPos : SV_GroupThreadID;
    uint3 globalPos : SV_DispatchThreadID;
};

[[shader("compute")]]
[numthreads(8, 8, 4)]
void main(ComputeInput input) {
	if (any(input.globalPos >= Froxel_Resolution)) return;

    float3 seed = input.globalPos + float3(3,9,13)*ap.timing.frameCounter;
    float3 bufferPos = input.globalPos + hash33(seed);

    float3 ndcPos = Froxel_GetNdcPosition(bufferPos);

    float depth = ap.depth.sampleNearest(ndcPos.xy * 0.5 + 0.5);
    if (depth > 0.0) ndcPos.z = max(ndcPos.z, depth);

    float3 viewPos = mul_project(ap.camera.projectionInv, ndcPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);
    float3 localDir = normalize(localPos);

    float dither = hash13(seed);

    float3 sunDir = normalize(ap.celestial.sunPosition);
    float3 moonDir = normalize(ap.celestial.moonPosition);

    float3 skyPos = planet.getSkyPosition(localPos);

    float3 shadowViewPos = mul3(ap.celestial.view, localPos);

    float shadowF = 1.0;
    if (let result = getShadowCascade(shadowViewPos)) {
        shadowF = ap.opaqueShadow.compare(result.position.xy, result.cascade, result.position.z);
    }

    float VoL_sun = dot(localDir, sunDir);
    float miePhase_sun = getMiePhase(VoL_sun);

    float VoL_moon = dot(localDir, moonDir);
    float miePhase_moon = getMiePhase(VoL_moon);

    float3 skyLightDir = normalize(ap.celestial.position);
    float atmoDist = planet.rayIntersectsAtmosphere(skyPos, skyLightDir);
    // TODO: use min of ground dist?
    float stepDist = atmoDist / Froxel_SkyLight_StepCount;

    float3 scattering = 0.0;
    float3 transmittance = 1.0;

    for (int i = 0; i < Froxel_SkyLight_StepCount; i++) {
        float3 traceSkyPos = skyPos + i * stepDist * skyLightDir;

        AtmosphereSample skySample;
        float altitude_KM = planet.getSkyAltitude(traceSkyPos);
        sky.Sample(altitude_KM, skySample);

        float3 sampleTransmittance = exp(-stepDist * skySample.extinction);

        // Integrate within each segment.
        // float3 scatteringNoPhase = skySample.rayleighScattering + skySample.mieScattering;
        // float3 scatteringF = (scatteringNoPhase - scatteringNoPhase * sampleTransmittance) / skySample.extinction;
        // lumFactor += transmittance * scatteringF;

        float3 sunLight = planet.sampleTransmit(traceSkyPos, sunDir) * SunColor;
        float3 moonLight = planet.sampleTransmit(traceSkyPos, -sunDir) * MoonColor;

        float3 inScattering = skySample.mieScattering * (miePhase_sun * sunLight + miePhase_moon * moonLight) + Sky_MinLight;

        // Integrated scattering within path segment.
        float3 scatteringIntegral = (inScattering - inScattering * sampleTransmittance) / skySample.extinction;

        scattering += scatteringIntegral * transmittance;
        transmittance *= sampleTransmittance;
    }

    float3 indirect = planet.sampleMultiScatter(skyPos, sunDir);
    scattering = indirect + scattering * shadowF;


    // project last frame position and accumulate
    float3 bufferPosLast = input.globalPos + 0.5;
    float3 ndcPosLast = Froxel_GetNdcPosition(bufferPosLast);
    float3 viewPosLast = mul_project(ap.camera.projectionInv, ndcPosLast);
    float3 localPosLast = mul3(ap.camera.viewInv, viewPosLast);

    localPosLast += (ap.camera.position - ap.temporal.position);

    viewPosLast = mul3(ap.temporal.view, localPosLast);
    ndcPosLast = mul_project(ap.temporal.projection, viewPosLast);
    bufferPosLast = Froxel_GetBufferPosition(ndcPosLast);

    half4 froxelPrev = half4(0.0);
    if (Froxel_InBufferBounds(bufferPosLast)) {
        froxelPrev = texFroxel_read.Sample(froxelSampler, bufferPosLast / Froxel_Resolution);
    }

    half counter = (half)clamp(froxelPrev.a + 1.0, 1.0, Froxel_MaxFrames);
    half3 final = lerp(froxelPrev.rgb, half3(scattering), rcp(counter));

    texFroxel_write[input.globalPos] = half4(final, counter);
}
