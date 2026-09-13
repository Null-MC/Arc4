import aperture;
import settings;
import lib.common;
import lib.exposure;

extern static const float Exposure_Speed = 0.8;

[[vk::image_format("r32ui")]]
RWTexture2D<uint> texHistogram;

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

	InterlockedAdd(texHistogram[int2(input.groupIndex,0)], histogramBins[input.groupIndex].load());
}

[[shader("compute")]]
[numthreads(256)]
void compute(uint index : SV_GroupIndex) {
	uint countForThisBin = texHistogram[int2(index,0)];
	exposureBins[index] = countForThisBin * index;

	GroupMemoryBarrierWithGroupSync();

	if (!userSettings.Debug_Exposure) {
		texHistogram[int2(index,0)] = 0u;
	}

	// This loop will perform a weighted count of the luminance range
	for (uint cutoff = (256u >> 1u); cutoff > 0u; cutoff >>= 1u) {
		if (uint(index) < cutoff) {
			exposureBins[index] += exposureBins[index + cutoff];
		}

		GroupMemoryBarrierWithGroupSync();
	}

	if (index == 0) {
		float Exposure_numPixels = ap.game.screenSize.x * ap.game.screenSize.y;
		float nonBlackPixelCount = Exposure_numPixels - countForThisBin;
		float weightedLogAverage = (exposureBins[0] / max(nonBlackPixelCount, 1.0)) - 1.0;

		float Exposure_logLumRange = userSettings.Exposure_Max - userSettings.Exposure_Min;
		float Exposure_logLumRangeInv = rcp(Exposure_logLumRange);

		// Map from our histogram space to actual luminance
		float weightedAvg = (weightedLogAverage/254.0 * Exposure_logLumRange) + userSettings.Exposure_Min;
		float weightedAvgLum = exp2(weightedAvg + userSettings.Exposure_Offset);
		float adaptedLum = weightedAvgLum;

		// do not mix if first rendered frame
		if (ap.timing.frameCounter > 0) {
			float timeF = 1.0 - exp(-max(Exposure_Speed * ap.timing.lastFrameTime, 1.0e-12));

			float lumLastFrame = clamp(exposure[0].average, 0.0, 65000.0);
			adaptedLum = lumLastFrame + (weightedAvgLum - lumLastFrame) * timeF;
		}

		exposure[0].average = adaptedLum;
	}
}

[[shader("compute")]]
[numthreads(256)]
void clear(uint index : SV_GroupIndex) {
    texHistogram[int2(index,0)] = 0u;
}
