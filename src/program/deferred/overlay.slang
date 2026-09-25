import aperture;
import settings;


[[vk::image_format("rgba16f")]]
RWTexture2D<float3> texMain_write;

Texture2D<half3> texMain_read;

Texture2D<half4> texWeather;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    float3 color = texMain_read[globalPos];

    if (!userSettings.Accumulation) {
        float4 weather = texWeather[globalPos];

        float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
        float3 blurred = texMain_read.SampleLevel(apt_linearSampler, texcoord, 4).rgb;

        color.rgb = lerp(color.rgb, blurred, weather.a);

        color.rgb = lerp(color.rgb, weather.rgb, weather.a * 0.4);
    }

    color.rgb = clamp(color.rgb, 0.0, half.maxValue);
    texMain_write[globalPos] = color.rgb;
}
