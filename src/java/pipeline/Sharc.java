package pipeline;

import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

import lib.Shader.ShaderBuilder;

public class Sharc {
    private static final int THREADS_1D = 256;
    private static final int MIN_BUCKET_COUNT = 1 << 16;
    private static final int MAX_BUCKET_COUNT = 1 << 20;
    private static final int PIXELS_PER_BUCKET = 8;
    private static final int CASCADE_COUNT = 4;
    private static final int HASH_ENTRY_STRIDE_BYTES = 24;
    private static final int ACCUMULATION_ENTRY_STRIDE_BYTES = 16;
    private static final int RESOLVED_ENTRY_STRIDE_BYTES = 16;
    private static final int UPDATE_TILE_SIZE = 4;

    private final int bucketCount;


    public Sharc(Screen screen, PipelineConfig pipeline) {
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

    public void render(StageList stage, ShaderBuilder builder, Texture2D diffuseWriter) {
        builder.compute(stage, "SHARC-Clear", "program/deferred/sharc/clear", shader -> {
            shader.dispatch1D(bucketCount, THREADS_1D);
        });

        builder.compute(stage, "SHARC-Update", "program/deferred/sharc/update", shader -> {
            shader.exportInt("SHARC_UPDATE_TILE_SIZE", UPDATE_TILE_SIZE);
            shader.dispatchRenderSize(UPDATE_TILE_SIZE * 16, UPDATE_TILE_SIZE * 16);
        });

        builder.compute(stage, "SHARC-Resolve", "program/deferred/sharc/resolve", shader -> {
            shader.dispatch1D(bucketCount, THREADS_1D);
        });

        builder.compute(stage, "SHaRC-Render", "program/deferred/sharc/render", shader -> {
            shader.override("texDiffuse_write", diffuseWriter);
            shader.dispatchRenderSize(16, 16);
        });
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
