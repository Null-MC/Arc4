import java.util.function.Consumer;

import dev.irisshaders.aperture.api.*;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.*;
import dev.irisshaders.aperture.api.pipeline.*;
import dev.irisshaders.aperture.api.renderer.*;
import lib.HillaireSky;
import lib.PingPongBuffer;
import lib.PingPongBufferBuilder;
import lib.Accumulation;


public class main implements ShaderPack {
    private static final int CASCADE_COUNT = 4;

    public final HillaireSky sky = new HillaireSky();

    private Accumulation accumulation;
    private PingPongBuffer mainTexture;
    // private Froxels froxels;


    @Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
        sky.Initialize(pipeline);

        if (pipeline.settings().getBoolValue("Accumulation"))
            accumulation = new Accumulation(pipeline);

        // froxels = new Froxels(pipeline, screen);

        pipeline.loadPNGTexture("blueNoiseTexture", "assets/blue_noise_64.png");

        pipeline.sampler("blueNoiseSampler")
            .addressMode(AddressMode.REPEAT)
            .minFilter(FilterMode.NEAREST)
            .magFilter(FilterMode.NEAREST)
            .create();

        mainTexture = new PingPongBufferBuilder(pipeline, "mainTexture", TextureFormat.RGBA16_SFLOAT)
            .windowSize()
            .createEmpty();

        var texOpaqueColor = pipeline.texture2D("texOpaqueColor", TextureFormat.RGBA8_UNORM)
            .renderSize()
            .create();

        var texOpaqueNormal = pipeline.texture2D("texOpaqueNormal", TextureFormat.RG16_SFLOAT)
            .renderSize()
            .create();

        withStage(pipeline, ProgramStage.PRE_RENDER, stage -> {
            sky.renderTransmit(stage);
            sky.renderMultiScatter(stage);
            sky.renderView(stage);
        });
        
        pipeline.object(ProgramUsage.SHADOW, "object/shadow", "ShadowShader");

        pipeline.object(ProgramUsage.SKYBOX, "object/discard", "DiscardShader");
        pipeline.object(ProgramUsage.SKY_TEXTURES, "object/discard", "DiscardShader");
        pipeline.object(ProgramUsage.CLOUDS, "object/discard", "DiscardShader");

        pipeline.object(ProgramUsage.BASIC, "object/deferred", "DeferShader")
            .writes("color", texOpaqueColor)
            .writes("normal", texOpaqueNormal);

        // pipeline.object(ProgramUsage.TRANSLUCENT, "object/basic", "BasicShader")
        //     .writes("color", mainTexture)
        //     .exportInt("CASCADE_COUNT", CASCADE_COUNT);
        
        withStage(pipeline, ProgramStage.POST_RENDER, stage -> {
            var sizeX_16 = (int)Math.ceil(screen.renderWidth() / 16f);
            var sizeY_16 = (int)Math.ceil(screen.renderHeight() / 16f);
            
            stage.compute("OpaqueDeferred", "deferred/opaque", "main")
                .dispatch2D(sizeX_16, sizeY_16);
            
            // froxels.render(stage);

            mainTexture.flip();

            stage.compute("Volumetric", "deferred/volumetric", "main")
                .dispatch2D(sizeX_16, sizeY_16);

            mainTexture.flip();

            if (accumulation != null) {
                accumulation.render(stage, screen);

                mainTexture.flip();
            }

            stage.compute("Tonemap", "post/tonemap", "main")
                .dispatch2D(sizeX_16, sizeY_16);

            mainTexture.flip();

            if (accumulation != null) {
                stage.compute("Sharpen", "post/sharpen", "main")
                    .dispatch2D(sizeX_16, sizeY_16);

                mainTexture.flip();
            }
        });

        pipeline.combinationPass("post/final");
    }

    @Override
	public void configureRenderer(RendererConfig rendererConfig) {
        var settings = rendererConfig.getSettings();

        rendererConfig.setShadowCascades(CASCADE_COUNT);
        rendererConfig.setShadowDistance(400.0f);
        rendererConfig.setShadowResolution(settings.getIntValue("Shadow_Resolution"));
    }

    @Override
	public void onNewFrame(FrameState state) {
        if (accumulation != null) accumulation.update();

        var rendererConfig = state.getRendererConfig();
        var settings = rendererConfig.getSettings();

        rendererConfig.setSunPathRotation(settings.getFloatValue("SunAngle"));
    }

    private void withStage(PipelineConfig pipeline, ProgramStage programStage, Consumer<StageList> callback) {
        callback.accept(pipeline.stage(programStage));
    }
}
