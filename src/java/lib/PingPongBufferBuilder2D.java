package lib;

import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.objects.UnbuiltTexture2D;
import dev.irisshaders.aperture.api.objects.UnbuiltTextureReference2D;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class PingPongBufferBuilder2D {
    private final UnbuiltTexture2D texture_A;
    private final UnbuiltTexture2D texture_B;
    private final UnbuiltTextureReference2D reader;
    private final UnbuiltTextureReference2D writer;


    public PingPongBufferBuilder2D(PipelineConfig pipeline, String name, TextureFormat format) {
        texture_A = pipeline.texture2D(name+"_A", format);
        texture_B = pipeline.texture2D(name+"_B", format);

        reader = pipeline.reference2D(name+"_read", format);
        writer = pipeline.reference2D(name+"_write", format);
    }

    public PingPongBufferBuilder2D renderSize() {
        texture_A.renderSize();
        texture_B.renderSize();
        reader.renderSize();
        writer.renderSize();
        return this;
    }

    public PingPongBufferBuilder2D windowSize() {
        texture_A.windowSize();
        texture_B.windowSize();
        reader.windowSize();
        writer.windowSize();
        return this;
    }

    public PingPongBuffer2D createEmpty() {
        return new PingPongBuffer2D(
            texture_A.create(),
            texture_B.create(),
            reader.createEmpty(),
            writer.createEmpty());
    }

    public PingPongBuffer2D createFilled() {
        return new PingPongBuffer2D(
            texture_A.create(),
            texture_B.create(),
            reader.createFilled(),
            writer.createFilled());
    }
}
