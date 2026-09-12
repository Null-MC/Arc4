package lib;

import dev.irisshaders.aperture.api.commands.ComputeCommand;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class Accumulation {
    private final PingPongBuffer textureSet;


    public Accumulation(PipelineConfig pipeline) {
        textureSet = new PingPongBufferBuilder(pipeline, "texAccumulate", TextureFormat.RGBA16_SFLOAT)
            .windowSize()
            .createEmpty();
    }

    public void flip() {
        textureSet.flip();
    }

    public ComputeCommand render(StageList stage, Screen screen) {
        var sizeX = (int)Math.ceil(screen.renderWidth() / 16f);
        var sizeY = (int)Math.ceil(screen.renderHeight() / 16f);
        
        return stage.compute("Accumulate", "post/accumulate", "main")
            .dispatch2D(sizeX, sizeY);
    }
}
