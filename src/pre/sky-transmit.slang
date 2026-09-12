import aperture;
import lib.common;
import lib.ign;
import lib.sky.shared;
import lib.sky.transmit;


extern static const int BufferWidth;
extern static const int BufferHeight;

static const int sunTransmittanceSteps = 8;

[[vk::image_format("rgba16f")]]
RWTexture2D<half3> texSkyTransmit;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    float2 uv = (globalPos.xy + 0.5) / float2(BufferWidth, BufferHeight);
    if (!all(globalPos < uint2(BufferWidth, BufferHeight))) return;

    var planet = HillaireSky::currentPlanet();
    var sky = HillaireSky::currentSky();

    float3 pos, sunDir;
    HillaireSky::fromTransmitCoord(uv, planet, pos, sunDir);

    float3 transmittance = 0.0;
    if (planet.rayIntersectsGround(pos, sunDir) <= 0.0) {
        float atmoDist = planet.rayIntersectsAtmosphere(pos, sunDir);
        
        float dither = InterleavedGradientNoiseTime(globalPos);
        float stepSize = atmoDist / sunTransmittanceSteps;

        float3 accumDepth = float3(0.0);

        for (int i = 0; i < sunTransmittanceSteps; i++) {
            float t = (i + dither) * stepSize;
            float3 newPos = pos + t*sunDir;
            
            AtmosphereSample sample;
            float altitude_KM = planet.getSkyAltitude(newPos);
            sky.Sample(altitude_KM, sample);
            
            accumDepth += sample.extinction;
        }

        transmittance = exp(-stepSize * accumDepth);
    }

    half3 color_new = half3(saturate(transmittance));

    half3 color = texSkyTransmit[globalPos];
    color = ap.timing.frameCounter < 1 ? color_new : lerp(color, color_new, half3(0.0625));
    texSkyTransmit[globalPos] = color;
}
