package pipeline;

import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class Sharc {
    private static final int THREADS_1D = 256;
    private static final int MIN_BUCKET_COUNT = 1 << 16;
    private static final int MAX_BUCKET_COUNT = 1 << 20;
    private static final int PIXELS_PER_BUCKET = 8;
    private static final int CASCADE_COUNT = 4;
    private static final int HASH_ENTRY_STRIDE_BYTES = 24;
    private static final int ACCUMULATION_ENTRY_STRIDE_BYTES = 16;
    private static final int RESOLVED_ENTRY_STRIDE_BYTES = 16;

    private final Screen screen;
    private final int bucketCount;


    public Sharc(Screen screen, PipelineConfig pipeline) {
        this.screen = screen;

        int pixelCount = screen.renderWidth() * screen.renderHeight();
        bucketCount = nextPowerOfTwo(clamp(
            (pixelCount + PIXELS_PER_BUCKET - 1) / PIXELS_PER_BUCKET,
            Math.max(MIN_BUCKET_COUNT, CASCADE_COUNT),
            MAX_BUCKET_COUNT));
        if (bucketCount % CASCADE_COUNT != 0) {
            throw new IllegalStateException("SHARC bucket count must divide evenly across cascades");
        }

        pipeline.buffer("sharcHashEntries", bucketCount * HASH_ENTRY_STRIDE_BYTES);
        pipeline.buffer("sharcAccumulation", bucketCount * ACCUMULATION_ENTRY_STRIDE_BYTES);
        pipeline.buffer("sharcResolved", bucketCount * RESOLVED_ENTRY_STRIDE_BYTES);
    }

    public void render(StageList stage) {
        var sizeX_16 = (int)Math.ceil(screen.renderWidth() / 16f);
        var sizeY_16 = (int)Math.ceil(screen.renderHeight() / 16f);

        stage.compute("SHARC-Clear", "program/deferred/sharc-clear", "main")
            .exportInt("SHARC_BUCKET_COUNT", bucketCount)
            .dispatch1D((int)Math.ceil(bucketCount / (float)THREADS_1D));

        stage.compute("SHARC-Update", "program/deferred/sharc-update", "main")
            .exportInt("SHARC_BUCKET_COUNT", bucketCount)
            .dispatch2D(sizeX_16, sizeY_16);

        stage.compute("SHARC-Resolve", "program/deferred/sharc-resolve", "main")
            .exportInt("SHARC_BUCKET_COUNT", bucketCount)
            .dispatch1D((int)Math.ceil(bucketCount / (float)THREADS_1D));
    }

    public int bucketCount() {
        return bucketCount;
    }

    private static int clamp(int value, int minimum, int maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    private static int nextPowerOfTwo(int value) {
        int result = 1;
        while (result < value) result <<= 1;
        return result;
    }
}
