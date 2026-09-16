import aperture;
import lib.sharc;

[[shader("compute")]]
[numthreads(256)]
void main(uint index : SV_DispatchThreadID) {
    if (index >= SHARC_BUCKET_COUNT) return;

    if (sharcHashEntries[index].key != SHARC_EMPTY_KEY &&
        sharcHashEntries[index].key != SHARC_TOMBSTONE_KEY &&
        ap.timing.frameCounter - sharcHashEntries[index].lock > SHARC_STALE_FRAME_MAX) {
        sharcHashEntries[index].key = SHARC_TOMBSTONE_KEY;
        sharcHashEntries[index].lock = 0u;
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
