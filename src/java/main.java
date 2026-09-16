import java.util.function.Consumer;

import dev.irisshaders.aperture.api.*;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.*;
import dev.irisshaders.aperture.api.pipeline.*;
import dev.irisshaders.aperture.api.renderer.*;

import pipeline.Froxels;
import pipeline.BlockMap;
import pipeline.Bloom;
import pipeline.Exposure;
import pipeline.HillaireSky;
import pipeline.Resources;
import lib.Flipper;


public class main implements ShaderPack {
    private static final int CASCADE_COUNT = 4;

    private HillaireSky sky;
    private Exposure exposure;
    private Froxels froxels;
    private Bloom bloom;
    private Resources resources;
    private Flipper<Texture2D> mainFlipper;
    private Flipper<Texture2D> diffuseFlipper;
    private Flipper<Texture2D> specularFlipper;
    private BlockMap blocks = new BlockMap();


    @Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
        resources = new Resources(screen, pipeline);

        diffuseFlipper = new Flipper<Texture2D>(resources.texDiffuse_A, resources.texDiffuse_B);
        specularFlipper = new Flipper<Texture2D>(resources.texSpecular_A, resources.texSpecular_B);
        mainFlipper = new Flipper<Texture2D>(resources.mainTexture_A, resources.mainTexture_B);

        sky = new HillaireSky(pipeline);
        exposure = new Exposure(screen, pipeline);
        froxels = new Froxels(screen, pipeline);

        if (pipeline.settings().getBoolValue("Bloom_Enabled")) {
            bloom = new Bloom(screen, pipeline);
        }

        withStage(pipeline, ProgramStage.PRE_RENDER, stage -> {
            sky.renderTransmit(stage);
            sky.renderMultiScatter(stage);
            sky.renderView(stage);
        });
        
        pipeline.object(ProgramUsage.SHADOW, "program/object/shadow", "ShadowShader");

        pipeline.object(ProgramUsage.SKYBOX, "program/object/discard", "DiscardShader");
        pipeline.object(ProgramUsage.SKY_TEXTURES, "program/object/discard", "DiscardShader");
        pipeline.object(ProgramUsage.CLOUDS, "program/object/discard", "DiscardShader");

        pipeline.object(ProgramUsage.BASIC, "program/object/defer", "DeferShader")
            .writes("color", resources.texDeferColor, BlendMode.NONE)
            .writes("normal", resources.texDeferNormal, BlendMode.NONE)
            .writes("specular", resources.texDeferSpecular, BlendMode.NONE)
            .writes("data", resources.texDeferData, BlendMode.NONE);

        pipeline.object(ProgramUsage.TRANSLUCENT, "program/object/defer", "DeferShader")
            .exportBool("IsTranslucent", true)
            .writes("color", resources.texDeferColor, BlendMode.NONE)
            .writes("normal", resources.texDeferNormal, BlendMode.NONE)
            .writes("specular", resources.texDeferSpecular, BlendMode.NONE)
            .writes("data", resources.texDeferData, BlendMode.NONE);

        // pipeline.object(ProgramUsage.TRANSLUCENT, "program/object/basic", "BasicShader")
        //     .writes("color", mainTexture)
        //     .exportInt("CASCADE_COUNT", CASCADE_COUNT);
        
        withStage(pipeline, ProgramStage.POST_RENDER, stage -> {
            var sizeX_16 = (int)Math.ceil(screen.renderWidth() / 16f);
            var sizeY_16 = (int)Math.ceil(screen.renderHeight() / 16f);

            froxels.render(stage);
            
            stage.compute("Deferred-Diffuse", "program/deferred/diffuse", "main")
                .overrideObject("texDiffuse_write", diffuseFlipper.getWriter().name())
                .dispatch2D(sizeX_16, sizeY_16);

            diffuseFlipper.flip();
                         
            stage.compute("Deferred-Specular", "program/deferred/specular", "main")
                .overrideObject("texSpecular_write", specularFlipper.getWriter().name())
                .dispatch2D(sizeX_16, sizeY_16);

            specularFlipper.flip();
   

            // TODO: blur

            // if (pipeline.settings().getBoolValue("Accumulation")) {
            //     stage.compute("Accumulate-Diffuse", "program/deferred/accumulate", "main")
            //         .overrideObject("texDiffuse_read", diffuseFlipper.getReader().name())
            //         .overrideObject("texDiffuse_write", diffuseFlipper.getWriter().name())
            //         .dispatch2D(sizeX_16, sizeY_16);

            //     diffuseFlipper.flip();
            // }

            stage.compute("OpaqueDeferred", "program/deferred/opaque", "main")
                .overrideObject("texDiffuse_read", diffuseFlipper.getReader().name())
                .overrideObject("texSpecular_read", specularFlipper.getReader().name())
                .overrideObject("texMain_write", mainFlipper.getWriter().name())
                .dispatch2D(sizeX_16, sizeY_16);
            
            mainFlipper.flip();

            stage.compute("Volumetric", "program/deferred/volumetric", "main")
                .overrideObject("texMain_read", mainFlipper.getReader().name())
                .overrideObject("texMain_write", mainFlipper.getWriter().name())
                .exportInt("Froxel_Width", froxels.BufferWidth)
                .exportInt("Froxel_Height", froxels.BufferHeight)
                .exportInt("Froxel_Depth", froxels.BufferDepth)
                .dispatch2D(sizeX_16, sizeY_16);

            mainFlipper.flip();

            if (pipeline.settings().getBoolValue("TAA_Enabled")) {
                stage.compute("TAA", "program/post/taa", "main")
                    .overrideObject("texMain_read", mainFlipper.getReader().name())
                    .overrideObject("texMain_write", mainFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);

                mainFlipper.flip();
            }

            if (bloom != null) {
                bloom.render(stage, mainFlipper.getReader());
                // do not flip, writes to reader!
            }

            exposure.render(stage, mainFlipper.getReader());
            
            stage.compute("Tonemap", "program/post/tonemap", "main")
                .overrideObject("tex_read", mainFlipper.getReader().name())
                .overrideObject("tex_write", mainFlipper.getWriter().name())
                .dispatch2D(sizeX_16, sizeY_16);

            mainFlipper.flip();

            if (pipeline.settings().getBoolValue("TAA_Enabled")) {
                // TAA CAS Sharpening
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
        resources.update(state);
        froxels.update();

        var rendererConfig = state.getRendererConfig();
        var settings = rendererConfig.getSettings();

        rendererConfig.setSunPathRotation(settings.getFloatValue("SunAngle"));
    }

    @Override
	public int setBlockId(IBlockState block) {
		return blocks.getId(block);
	}

    private void withStage(PipelineConfig pipeline, ProgramStage programStage, Consumer<StageList> callback) {
        callback.accept(pipeline.stage(programStage));
    }
}
