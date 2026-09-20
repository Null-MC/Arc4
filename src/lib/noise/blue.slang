public module blue_noise;

Texture2D<half4> blueNoiseTexture;
SamplerState blueNoiseSampler;


namespace BlueNoise {

    half4 sample(float2 uv) {
        return blueNoiseTexture.SampleLevel(blueNoiseSampler, uv, 0.0);
    }

    float sampleAnimated1D(const in int2 pixel, const in int sampleIndex, const in int frame) {
        // int2 texelCoord = (pixel + int2(23, 47) * sampleIndex) % 64;
        // float2 uv = (float2(texelCoord) + 0.5) / 64.0;

        // // .x/.z are independently-generated blue-noise channels: alternate them per sample
        // // index instead of re-scrambling the same channel with a hash every draw.
        // half4 noise4 = sample(uv);
        // float noise = (sampleIndex & 1) == 0 ? noise4.x : noise4.z;

        // const float goldenRatioConjugate = 0.6180339887;
        // return frac(noise + float(frame) * goldenRatioConjugate);

        int2 texelCoord = (pixel + int2(23, 47) * sampleIndex) % 64;
        float2 uv = (float2(texelCoord) + 0.5) / 64.0;

        half4 noise4 = sample(uv);
        // Maintain the channel alternation logic
        float noise = (sampleIndex & 1) == 0 ? noise4.x : noise4.z;

        // Convert to 8-bit int for bitwise scrambling
        uint noiseInt = uint(clamp(noise * 255.0, 0.0, 255.0));

        // Generate a unique scrambler for this frame, sample index, and dimension
        uint scramble = hash31(uint3(pixel, uint(frame + sampleIndex * 13)));
        noiseInt ^= (scramble & 255u);

        return float(noiseInt) / 255.0;
    }

    float2 sampleAnimated2D(const in int2 pixel, const in int sampleIndex, const in int frame) {
        // int2 texelCoord = (pixel + int2(23, 47) * sampleIndex) % 64;
        // float2 uv = (float2(texelCoord) + 0.5) / 64.0;

        // // R/G and B/A are independently-generated blue-noise channels (not spatial shifts of the
        // // same channel), so the two axes no longer inherit a fixed grid-aligned correlation like
        // // the old two-tap offset approach produced.
        // half4 noise4 = sample(uv);
        // float2 noise = (sampleIndex & 1) == 0 ? noise4.xy : noise4.zw;

        // const float2 frameRotation = float2(0.754877666, 0.569840296) * float(frame);
        // return frac(noise + frameRotation);

        int2 texelCoord = (pixel + int2(23, 47) * sampleIndex) % 64;
        float2 uv = (float2(texelCoord) + 0.5) / 64.0;

        half4 noise4 = sample(uv);
        // Split dimensions cleanly between xy and zw
        float2 noise = (sampleIndex & 1) == 0 ? noise4.xy : noise4.zw;

        uint noiseIntX = uint(clamp(noise.x * 255.0, 0.0, 255.0));
        uint noiseIntY = uint(clamp(noise.y * 255.0, 0.0, 255.0));

        // Generate independent hashes per dimension, incorporating both frame and sample index
        uint scrambleX = hash31(uint3(pixel, uint(frame * 2 + sampleIndex * 31 + 0)));
        uint scrambleY = hash31(uint3(pixel, uint(frame * 2 + sampleIndex * 31 + 1)));

        float x = float(noiseIntX ^ (scrambleX & 255u)) / 255.0;
        float y = float(noiseIntY ^ (scrambleY & 255u)) / 255.0;

        return float2(x, y);
    }

    // Fixed hash function for scrambling
    uint hash31(uint3 v) {
        v ^= v.yzx * uint3(1023, 2047, 4095);
        v ^= v >> uint3(7, 3, 5);
        v *= uint3(12345, 67890, 23456);
        return v.x ^ v.y ^ v.z;
    }

}

