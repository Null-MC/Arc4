package pipeline;

import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

import lib.Flipper;

public class Exposure {
    private final Screen screen;
    private final PipelineConfig pipeline;

    
    public Exposure(Screen screen, PipelineConfig pipeline) {
        this.screen = screen;
        this.pipeline = pipeline;

        pipeline.texture1D("texHistogram", TextureFormat.R32_UINT)
            .size(256)
            .create();

        pipeline.buffer("exposure", 4);
    }

    public void render(StageList stage, Texture2D texMain_read) {
        var sizeX_16 = (int)Math.ceil(screen.renderWidth() / 16f);
        var sizeY_16 = (int)Math.ceil(screen.renderHeight() / 16f);

        if (pipeline.settings().getBoolValue("Debug_Exposure")) {
            stage.compute("histogram-clear", "program/post/histogram", "clear")
                .dispatch1D(1);
        }

        stage.compute("Histogram-Build", "program/post/histogram", "build")
            .overrideObject("texMain_read", texMain_read.name())
            .dispatch2D(sizeX_16, sizeY_16);

        stage.compute("Histogram-Compute", "program/post/histogram", "compute")
            .dispatch1D(1);
    }
}
