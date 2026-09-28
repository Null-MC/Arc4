import aperture;
import settings;
import lib.common;
import lib.exposure;

extern static const float Exposure_Speed = 0.8;

[[vk::image_format("r32ui")]]
RWTexture1D<uint> texHistogram;

Texture2D<half3> texMain_read;

groupshared Atomic<uint> histogramBins[256];
groupshared uint exposureBins[256];


uint colorToBin(const in float3 hdrColor, const in float minLogLum, const in float inverseLogLumRange) {
	float lum = luminance(hdrColor);
	if (lum < 1e-8) return 0u;

	float logLum = saturate((log2(lum) - minLogLum) * inverseLogLumRange);
	return uint(logLum * 254.0 + 1.0);
}


struct ComputeInput {
    uint groupIndex : SV_GroupIndex;
    uint2 globalPos : SV_DispatchThreadID;
};

[[shader("compute")]]
[numthreads(16, 16)]
void build(ComputeInput input) {
	histogramBins[input.groupIndex] = 0u;
	GroupMemoryBarrierWithGroupSync();

	int2 uv = int2(input.globalPos);
	if (all(uv < int2(ap.game.screenSize))) {
		float3 hdrColor = texMain_read[uv].rgb;

		float Exposure_logLumRange = userSettings.Exposure_Max - userSettings.Exposure_Min;
		float Exposure_logLumRangeInv = rcp(Exposure_logLumRange);

		uint binIndex = colorToBin(hdrColor, userSettings.Exposure_Min, Exposure_logLumRangeInv);
		histogramBins[binIndex].increment();
	}

	GroupMemoryBarrierWithGroupSync();

	InterlockedAdd(texHistogram[input.groupIndex], histogramBins[input.groupIndex].load());
}

[[shader("compute")]]
[numthreads(256)]
void compute(uint index : SV_GroupIndex) {
	uint countForThisBin = texHistogram[index];

	// Store counts in groupshared memory for our parallel prefix sum
	exposureBins[index] = countForThisBin * index;
	GroupMemoryBarrierWithGroupSync();

	// Parallel Prefix Sum (Exclusive Scan) to find cumulative pixel counts
	// This lets every bin know exactly how many pixels lie below it.
	for (uint stride = 1; stride < 256; stride *= 2) {
		uint val = 0;
		if (index >= stride) {
			val = exposureBins[index - stride];
		}
		GroupMemoryBarrierWithGroupSync();

		exposureBins[index] += val;
		GroupMemoryBarrierWithGroupSync();
	}

	// Calculate total pixel count from the final element
	uint totalPixelCount = exposureBins[255];

	// Exclusive sum value: total pixels strictly in bins *below* this thread's bin
	uint cumulativeCountBelow = (index == 0) ? 0 : exposureBins[index - 1];

	// Optional: Clear the texture if debug is disabled
	if (!userSettings.Debug_Exposure) {
		texHistogram[index] = 0u;
	}

	// 3. Define Low and High Trim Cutoffs (e.g., discard bottom 10% and top 10%)
	// You can also expose these to userSettings (e.g., userSettings.Exposure_LowTrim)
	float lowPercentage = 0.10;
	float highPercentage = 0.10;

	uint lowPixelThreshold  = uint(float(totalPixelCount) * lowPercentage);
	uint highPixelThreshold = uint(float(totalPixelCount) * (1.0 - highPercentage));

	// Determine how many pixels in this specific bin fit within our safe threshold bounds
	uint currentBinStart = cumulativeCountBelow;
	uint currentBinEnd   = cumulativeCountBelow + countForThisBin;

	// Clamp the bin ranges to our safe region limits
	uint safeStart = clamp(currentBinStart, lowPixelThreshold, highPixelThreshold);
	uint safeEnd   = clamp(currentBinEnd,   lowPixelThreshold, highPixelThreshold);
	uint validPixelsInThisBin = safeEnd - safeStart;

	// 4. Repurpose groupshared memory for Weighted Value Reduction
	// Index 0 represents the minimum bin value mapping (-1.0 logic in your math)
	exposureBins[index] = validPixelsInThisBin * index;
	
	// We also need to count total valid pixels that survived the filtering pass
	// We reuse histogramBins from your globals to hold the pixel weights
	histogramBins[index].store(validPixelsInThisBin);

	GroupMemoryBarrierWithGroupSync();

	// 5. Traditional reduction loop for both weighted indices and pixel counters
	for (uint cutoff = (256u >> 1u); cutoff > 0u; cutoff >>= 1u) {
		if (index < cutoff) {
			exposureBins[index] += exposureBins[index + cutoff];
			histogramBins[index].add(histogramBins[index + cutoff].load());
		}

		GroupMemoryBarrierWithGroupSync();
	}

	// 6. Final math execution on Thread 0
	if (index == 0) {
		uint remainingPixels = histogramBins[0].load();

		// Prevent division by zero if a scene is totally uniform or empty
		float filteredLogAverage = 0.0;
		if (remainingPixels > 0) {
			filteredLogAverage = (float(exposureBins[0]) / float(remainingPixels)) - 1.0;
		}

		float Exposure_logLumRange = userSettings.Exposure_Max - userSettings.Exposure_Min;

		// Map from our histogram space back to actual HDR luminance
		float weightedAvg = (filteredLogAverage / 254.0 * Exposure_logLumRange) + userSettings.Exposure_Min;
		float weightedAvgLum = exp2(weightedAvg + userSettings.Exposure_Offset);
		float adaptedLum = weightedAvgLum;

		// Temporal smoothing mix over sequential frames
		// do not mix if first rendered frame
		if (ap.timing.frameCounter > 0) {
			float timeF = 1.0 - exp(-max(Exposure_Speed * ap.timing.lastFrameTime, 1.0e-12));

			float lumLastFrame = clamp(exposure[0].average, 0.0, half.maxValue);
			adaptedLum = lumLastFrame + (weightedAvgLum - lumLastFrame) * timeF;
		}

		exposure[0].average = adaptedLum;
	}
}

[[shader("compute")]]
[numthreads(256)]
void clear(uint index : SV_GroupIndex) {
    texHistogram[index] = 0u;
}
