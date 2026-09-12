package lib;

import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.objects.UnbuiltTexture2D;
import dev.irisshaders.aperture.api.objects.UnbuiltTextureReference;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class PingPongBufferBuilder {
    private final UnbuiltTexture2D texture_A;
    private final UnbuiltTexture2D texture_B;
    private final UnbuiltTextureReference reader;
    private final UnbuiltTextureReference writer;


    public PingPongBufferBuilder(PipelineConfig pipeline, String name, TextureFormat format) {
        texture_A = pipeline.texture2D(name+"_A", format);
        texture_B = pipeline.texture2D(name+"_B", format);

        reader = pipeline.reference(name+"_read", format);
        writer = pipeline.reference(name+"_write", format);
    }

    public PingPongBufferBuilder renderSize() {
        texture_A.renderSize();
        texture_B.renderSize();
        reader.renderSize();
        writer.renderSize();
        return this;
    }

    public PingPongBufferBuilder windowSize() {
        texture_A.windowSize();
        texture_B.windowSize();
        reader.windowSize();
        writer.windowSize();
        return this;
    }

    public PingPongBuffer createEmpty() {
        return new PingPongBuffer(
            texture_A.create(),
            texture_B.create(),
            reader.createEmpty(),
            writer.createEmpty());
    }

    public PingPongBuffer createFilled() {
        return new PingPongBuffer(
            texture_A.create(),
            texture_B.create(),
            reader.createFilled(),
            writer.createFilled());
    }
}
