public module blue_noise;

Texture2D<half> blueNoiseTexture;
SamplerState blueNoiseSampler;


float2 getAnimatedBlueNoise(const in int2 pixel, const in int sampleIndex, const in int frame) {
    int2 sampleOffset = int2(23, 47) * sampleIndex;
    int2 pixelA = pixel + sampleOffset;
    int2 pixelB = pixel + sampleOffset + int2(19, 37);

    float2 uvA = (float2(pixelA) + 0.5) / 64.0;
    float2 uvB = (float2(pixelB) + 0.5) / 64.0;
    float2 noise = float2(
        blueNoiseTexture.SampleLevel(blueNoiseSampler, uvA, 0.0),
        blueNoiseTexture.SampleLevel(blueNoiseSampler, uvB, 0.0));

    const float2 frameRotation = float2(0.754877666, 0.569840296) * float(frame);
    return frac(noise + frameRotation);
}
