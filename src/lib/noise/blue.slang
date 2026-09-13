public module blue_noise;

Texture2D<half> blueNoiseTexture;
SamplerState blueNoiseSampler;


namespace BlueNoise {

    float sample(float2 uv) {
        float r = blueNoiseTexture.SampleLevel(blueNoiseSampler, uv, 0.0);
        return r;// pow(r, 2.2);
    }

    float2 sampleAnimated2D(const in int2 pixel, const in int sampleIndex, const in int frame) {
        int2 sampleOffset = int2(23, 47) * sampleIndex;
        int2 pixelA = pixel + sampleOffset;
        int2 pixelB = pixel + sampleOffset + int2(19, 37);

        float2 uvA = (pixelA + 0.5) / 64.0;
        float2 uvB = (pixelB + 0.5) / 64.0;
        float2 noise = float2(sample(uvA), sample(uvB));

        const float2 frameRotation = float2(0.754877666, 0.569840296) * float(frame);
        return frac(noise + frameRotation);
    }

}
