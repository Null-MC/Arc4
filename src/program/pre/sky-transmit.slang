import aperture;
import settings;
import lib.common;
import lib.noise.ign;
import lib.sky.shared;
import lib.sky.transmit;


extern static const int BufferWidth;
extern static const int BufferHeight;

static const half historyBlendF = rcp(24.h);
static const int sunTransmittanceSteps = 20;

[[vk::image_format("rgba16")]]
RWTexture2D<half3> texSkyTransmit;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    float2 uv = (globalPos.xy + 0.5) / float2(BufferWidth, BufferHeight);
    if (!all(globalPos < uint2(BufferWidth, BufferHeight))) return;

    float3 pos, sunDir;
    HillaireSky::fromTransmitCoord(uv, planet, pos, sunDir);

    float3 transmittance = 0.0;
    if (planet.rayIntersectsGround(pos, sunDir) <= 0.0) {
        float atmoDist_KM = planet.rayIntersectsAtmosphere(pos, sunDir);
        
        float dither = IGN::getAnimated(globalPos);
        float stepSize = atmoDist_KM / sunTransmittanceSteps;

        float3 accumExtinction = 0.0;

        for (int i = 0; i < sunTransmittanceSteps; i++) {
            float t = (i + dither) * stepSize;
            float3 newPos = pos + t*sunDir;
            
            AtmosphereSample sample;
            float altitude_KM = planet.getSkyAltitude(newPos);
            sky.Sample(altitude_KM, sample);
            
            accumExtinction += sample.extinction;
        }

        transmittance = exp(-stepSize * accumExtinction);
    }

    half3 color_new = half3(saturate(transmittance));

    half3 color = texSkyTransmit[globalPos];
    color = ap.timing.frameCounter < 1 ? color_new : lerp(color, color_new, half3(historyBlendF));
    texSkyTransmit[globalPos] = color;
}
