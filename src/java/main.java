import java.util.function.Consumer;

import buffers.PlanetBuffer;
import buffers.SceneBuffer;
import buffers.SkyBuffer;
import dev.irisshaders.aperture.api.*;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.*;
import dev.irisshaders.aperture.api.pipeline.*;
import dev.irisshaders.aperture.api.renderer.*;
import lib.HillaireSky;
import lib.PingPongBuffer;
import lib.PingPongBufferBuilder;
import lib.Flipper;


public class main implements ShaderPack {
    private static final int CASCADE_COUNT = 4;

    public final HillaireSky sky = new HillaireSky();

    private Screen screen;
    private Flipper<Texture2D> mainFlipper;
    private Flipper<Texture2D> diffuseFlipper;
    private MappedBuffer<SceneBuffer> bufferScene;
    private PingPongBuffer diffuseHistory;
    private PingPongBuffer taaHistory;
    // private Froxels froxels;


    @Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
        this.screen = screen;

        sky.Initialize(pipeline);

        // froxels = new Froxels(pipeline, screen);

        pipeline.loadPNGTexture("blueNoiseTexture", "assets/blue_noise_64.png");

        pipeline.sampler("blueNoiseSampler")
            .addressMode(AddressMode.REPEAT)
            .minFilter(FilterMode.NEAREST)
            .magFilter(FilterMode.NEAREST)
            .create();

        var texOpaqueColor = pipeline.texture2D("texOpaqueColor", TextureFormat.RGBA8_UNORM)
            .renderSize()
            .create();

        var texOpaqueNormal = pipeline.texture2D("texOpaqueNormal", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        var texOpaqueSpecular = pipeline.texture2D("texOpaqueSpecular", TextureFormat.RGBA8_UNORM)
            .renderSize()
            .create();

        diffuseFlipper = new Flipper<Texture2D>(
            pipeline.texture2D("texDiffuse_A", TextureFormat.RGBA16_SFLOAT)
                .renderSize()
                .create(),
            pipeline.texture2D("texDiffuse_B", TextureFormat.RGBA16_SFLOAT)
                .renderSize()
                .create());

        if (pipeline.settings().getBoolValue("Accumulation")) {
            diffuseHistory = new PingPongBufferBuilder(pipeline, "texDiffuseHistory", TextureFormat.RGBA16_SFLOAT)
                .renderSize()
                .createEmpty();
        }

        mainFlipper = new Flipper<Texture2D>(
            pipeline.texture2D("mainTexture_A", TextureFormat.RGBA16_SFLOAT)
                .windowSize()
                .create(),
            pipeline.texture2D("mainTexture_B", TextureFormat.RGBA16_SFLOAT)
                .windowSize()
                .create());

        if (pipeline.settings().getBoolValue("TAA_Enabled")) {
            taaHistory = new PingPongBufferBuilder(pipeline, "texTaaHistory", TextureFormat.RGBA16_SFLOAT)
                .windowSize()
                .createEmpty();
        }

        bufferScene = pipeline.mappedBuffer("scene", SceneBuffer.class);

        var bufferPlanet = pipeline.mappedBuffer("planet", PlanetBuffer.class);
        bufferPlanet.write(PlanetBuffer.Earth);

        var bufferSky = pipeline.mappedBuffer("sky", SkyBuffer.class);
        bufferSky.write(SkyBuffer.Earth);

        withStage(pipeline, ProgramStage.PRE_RENDER, stage -> {
            sky.renderTransmit(stage);
            sky.renderMultiScatter(stage);
            sky.renderView(stage);
        });
        
        pipeline.object(ProgramUsage.SHADOW, "program/object/shadow", "ShadowShader");

        pipeline.object(ProgramUsage.SKYBOX, "program/object/discard", "DiscardShader");
        pipeline.object(ProgramUsage.SKY_TEXTURES, "program/object/discard", "DiscardShader");
        pipeline.object(ProgramUsage.CLOUDS, "program/object/discard", "DiscardShader");

        pipeline.object(ProgramUsage.BASIC, "program/object/deferred", "DeferShader")
            .writes("color", texOpaqueColor)
            .writes("normal", texOpaqueNormal)
            .writes("specular", texOpaqueSpecular);

        pipeline.object(ProgramUsage.TRANSLUCENT, "program/object/deferred", "DeferShader")
            .writes("color", texOpaqueColor)
            .writes("normal", texOpaqueNormal)
            .writes("specular", texOpaqueSpecular);

        // pipeline.object(ProgramUsage.TRANSLUCENT, "program/object/basic", "BasicShader")
        //     .writes("color", mainTexture)
        //     .exportInt("CASCADE_COUNT", CASCADE_COUNT);
        
        withStage(pipeline, ProgramStage.POST_RENDER, stage -> {
            var sizeX_16 = (int)Math.ceil(screen.renderWidth() / 16f);
            var sizeY_16 = (int)Math.ceil(screen.renderHeight() / 16f);
            
            stage.compute("Deferred-Diffuse", "program/deferred/diffuse", "main")
                .overrideObject("texDiffuse_write", diffuseFlipper.getWriter().name())
                .dispatch2D(sizeX_16, sizeY_16);

            diffuseFlipper.flip();
                
            // TODO: blur

            if (pipeline.settings().getBoolValue("Accumulation")) {
                stage.compute("Accumulate-Diffuse", "program/post/accumulate", "main")
                    .overrideObject("texDiffuse_read", diffuseFlipper.getReader().name())
                    .overrideObject("texDiffuse_write", diffuseFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);

                diffuseFlipper.flip();
            }

            stage.compute("OpaqueDeferred", "program/deferred/opaque", "main")
                .overrideObject("texDiffuse_read", diffuseFlipper.getReader().name())
                .overrideObject("tex_read", mainFlipper.getReader().name())
                .overrideObject("tex_write", mainFlipper.getWriter().name())
                .dispatch2D(sizeX_16, sizeY_16);
            
            // froxels.render(stage);

            mainFlipper.flip();

            stage.compute("Volumetric", "program/deferred/volumetric", "main")
                .overrideObject("tex_read", mainFlipper.getReader().name())
                .overrideObject("tex_write", mainFlipper.getWriter().name())
                .dispatch2D(sizeX_16, sizeY_16);

            mainFlipper.flip();

            if (pipeline.settings().getBoolValue("TAA_Enabled")) {
                stage.compute("TAA", "program/post/taa", "main")
                    .overrideObject("texMain_read", mainFlipper.getReader().name())
                    .overrideObject("texMain_write", mainFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);

                mainFlipper.flip();
            }

            stage.compute("Tonemap", "program/post/tonemap", "main")
                .overrideObject("tex_read", mainFlipper.getReader().name())
                .overrideObject("tex_write", mainFlipper.getWriter().name())
                .dispatch2D(sizeX_16, sizeY_16);

            mainFlipper.flip();

            if (pipeline.settings().getBoolValue("TAA_Enabled")) {
                stage.compute("Sharpen", "program/post/sharpen", "main")
                    .overrideObject("texMain_read", mainFlipper.getReader().name())
                    .overrideObject("texMain_write", mainFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);

                mainFlipper.flip();
            }
        });

        pipeline.combinationPass("program/post/final")
            .overrideObject("tex_read", mainFlipper.getReader().name());
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
        bufferScene.write(SceneBuffer.Build(state, screen));
        
        if (diffuseHistory != null) diffuseHistory.flip();
        if (taaHistory != null) taaHistory.flip();

        var rendererConfig = state.getRendererConfig();
        var settings = rendererConfig.getSettings();

        rendererConfig.setSunPathRotation(settings.getFloatValue("SunAngle"));
    }

    private void withStage(PipelineConfig pipeline, ProgramStage programStage, Consumer<StageList> callback) {
        callback.accept(pipeline.stage(programStage));
    }
}
