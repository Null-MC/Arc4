import aperture;
import lib.sharc;

[[shader("compute")]]
[numthreads(256)]
void main(uint index : SV_DispatchThreadID) {
    if (index >= SHARC_BUCKET_COUNT_U) return;

    if (sharcHashEntries[index].key.x != SHARC_EMPTY_KEY &&
        sharcHashEntries[index].key.x != SHARC_TOMBSTONE_KEY &&
        ap.timing.frameCounter - sharcHashEntries[index].normalFrame.w > SHARC_STALE_FRAME_MAX) {
        sharcHashEntries[index].key = uint2(SHARC_TOMBSTONE_KEY, SHARC_TOMBSTONE_KEY);
        sharcHashEntries[index].normalFrame = 0.0;
        sharcResolved[index].radiance = 0.0;
        sharcResolved[index].samples = 0.0;
    }

    SharcAccumulationEntry accumulation = sharcAccumulation[index];
    uint sampleCount = accumulation.samples;

    if (sampleCount > 0u) {
        float3 currentRadiance = float3(
            accumulation.radianceR,
            accumulation.radianceG,
            accumulation.radianceB
        ) / (float(sampleCount) * SHARC_RADIANCE_SCALE);

        SharcResolvedEntry previous = sharcResolved[index];
        float totalSamples = min(previous.samples + sampleCount, float(SHARC_MAX_HISTORY));
        float blend = sampleCount / max(totalSamples, 1.0);

        sharcResolved[index].radiance = lerp(previous.radiance, currentRadiance, blend);
        sharcResolved[index].samples = totalSamples;
    }

    sharcAccumulation[index].radianceR = 0u;
    sharcAccumulation[index].radianceG = 0u;
    sharcAccumulation[index].radianceB = 0u;
    sharcAccumulation[index].samples = 0u;
}
