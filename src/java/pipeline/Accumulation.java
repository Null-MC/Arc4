package pipeline;

import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import lib.PingPongBuffer2D;
import lib.PingPongBufferBuilder2D;

public class Accumulation {
    private final PingPongBuffer2D diffuseHistory;
    private final PingPongBuffer2D diffuseCounter;
    private final PingPongBuffer2D specularHistory;
    private final PingPongBuffer2D specularCounter;
    private final PingPongBuffer2D normalHistory;
    private final PingPongBuffer2D depthHistory;


    public Accumulation(PipelineConfig pipeline) {
        diffuseHistory = new PingPongBufferBuilder2D(pipeline, "texDiffuseHistory", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();
        
        diffuseCounter = new PingPongBufferBuilder2D(pipeline, "texDiffuseCounter", TextureFormat.R8_UINT)
            .renderSize()
            .createEmpty();

        specularHistory = new PingPongBufferBuilder2D(pipeline, "texSpecularHistory", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();

        specularCounter = new PingPongBufferBuilder2D(pipeline, "texSpecularCounter", TextureFormat.R8_UINT)
            .renderSize()
            .createEmpty();
        
        normalHistory = new PingPongBufferBuilder2D(pipeline, "texNormalHistory", TextureFormat.RG16_SFLOAT)
            .renderSize()
            .createEmpty();
        
        depthHistory = new PingPongBufferBuilder2D(pipeline, "texDepthHistory", TextureFormat.R32_SFLOAT)
            .renderSize()
            .createEmpty();
    }

    public void update() {
        diffuseHistory.flip();
        diffuseCounter.flip();
        specularHistory.flip();
        specularCounter.flip();
        normalHistory.flip();
        depthHistory.flip();
    }
}
