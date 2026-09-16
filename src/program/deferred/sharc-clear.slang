import aperture;
import lib.sharc;

[[shader("compute")]]
[numthreads(256)]
void main(uint index : SV_DispatchThreadID) {
    if (ap.timing.frameCounter != 0 || index >= SHARC_BUCKET_COUNT) return;

    sharcHashEntries[index].key = uint2(0u, 0u);
    sharcHashEntries[index].normalFrame = 0.0;
    sharcAccumulation[index].radianceR = 0u;
    sharcAccumulation[index].radianceG = 0u;
    sharcAccumulation[index].radianceB = 0u;
    sharcAccumulation[index].samples = 0u;
    sharcResolved[index].radiance = 0.0;
    sharcResolved[index].samples = 0.0;
}
