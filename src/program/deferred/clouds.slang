import aperture;
import settings;
import lib.common;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.clouds;
import lib.sky.trace;


extern static const int BufferWidth;
extern static const int BufferHeight;

[[vk::image_format("rgba16f")]]
RWTexture2D<float4> texDeferClouds;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= uint2(BufferWidth, BufferHeight))) return;

    float2 jitter = 0.5;
    if (userSettings.TAA_Enabled) {
        // jitter += scene.TAA_jitter*ap.game.renderSize;
    }

    float2 texcoord = (globalPos.xy + jitter) / float2(BufferWidth, BufferHeight);

    // float3 fragpos = toScreenSpace(float3(halfResTC * texelSize, 1.0));
    float3 clipPos = float3(texcoord * 2.0 - 1.0, 0.0);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    float3 viewDir = normalize(viewPos);
    float3 localDir = normalize(localPos);

    // float3 skyPos = planet.getSkyPosition(localPos);

    // float3 sunDir = normalize(ap.celestial.sunPosition);
    // float3 sunLight = SunColor * planet.sampleTransmit(skyPos, sunDir);
    // sunLight = getColorSpace().fromLinear(sunLight);

    // float3 moonDir = normalize(ap.celestial.moonPosition);
    // float3 moonLight = MoonColor * planet.sampleTransmit(skyPos, moonDir);
    // moonLight = getColorSpace().fromLinear(moonLight);

    // float noise = blueNoise(globalPos, ap.timing.frameCounter);
    float noise = BlueNoise::sampleAnimated1D(globalPos, 1, ap.timing.frameCounter);
    float4 color = renderClouds(viewDir, localDir, noise);

    if (!userSettings.Volumetric_Enabled) {
        float3 cameraSkyPos = planet.getSkyPosition(0.0);

        float planetDist = planet.rayIntersectsGround(cameraSkyPos, localDir);
        float cloudNearDist = rayIntersectSphere(cameraSkyPos, localDir, planet.RadiusGround_KM + cloud_height*0.001);
        float cloudFarDist  = rayIntersectSphere(cameraSkyPos, localDir, planet.RadiusGround_KM + maxHeight*0.001);

        float cloudDist = min(cloudNearDist, cloudFarDist);
        cloudDist = max(cloudDist, ap.camera.near);

        if (planetDist > 0.0 && planetDist < cloudDist) cloudDist = 0.0;
        
        if (cloudDist > 0.0) {
            // TODO: cheap sky trace without shadow sampling
            float3 sunDir = normalize(ap.celestial.sunPosition);

            float3 scattering;
            float3 transmittance;
            sky.raymarchScattering(scattering, transmittance, globalPos, cameraSkyPos, localDir, sunDir, cloudDist, 16);

            color.rgb = color.rgb * transmittance + scattering;
        }
    }

    // if (ap.timing.frameCounter > 0) {
    //     float4 color_last = texSkyClouds[globalPos];
    //     color = lerp(color_last, color, 0.0625);
    // }

    texDeferClouds[globalPos] = color;
}
