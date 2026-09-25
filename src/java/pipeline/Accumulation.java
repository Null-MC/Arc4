package pipeline;

import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import lib.PingPongBuffer2D;
import lib.PingPongBufferBuilder2D;

public class Accumulation {
    private final PingPongBuffer2D diffuseHistory;
    private final PingPongBuffer2D specularHistory;
    private final PingPongBuffer2D depthHistory;
    private final PingPongBuffer2D historyCounter;


    public Accumulation(PipelineConfig pipeline) {
        diffuseHistory = new PingPongBufferBuilder2D(pipeline, "texDiffuseHistory", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();

        specularHistory = new PingPongBufferBuilder2D(pipeline, "texSpecularHistory", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();
        
        depthHistory = new PingPongBufferBuilder2D(pipeline, "texDepthHistory", TextureFormat.R32_SFLOAT)
            .renderSize()
            .createEmpty();
        
        historyCounter = new PingPongBufferBuilder2D(pipeline, "texHistoryCounter", TextureFormat.R8_UINT)
            .renderSize()
            .createEmpty();
    }

    public void update() {
        diffuseHistory.flip();
        specularHistory.flip();
        depthHistory.flip();
        historyCounter.flip();
    }
}
