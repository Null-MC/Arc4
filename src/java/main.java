import java.util.function.Consumer;

import org.joml.Vector4f;

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
import pipeline.Sharc;
import pipeline.Water;
import pipeline.Accumulation;
import lib.Flipper;


public class main implements ShaderPack {
    private HillaireSky sky;
    private Exposure exposure;
    private Froxels froxels;
    private Bloom bloom;
    // private Water water;
    private Sharc sharc;
    private Accumulation accumulation;
    private Resources resources;
    private Flipper<Texture2D> mainFlipper;
    private Flipper<Texture2D> diffuseFlipper;
    private Flipper<Texture2D> specularFlipper;
    private BlockMap blocks = new BlockMap();


    @Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
        var settings = pipeline.settings();
        resources = new Resources(screen, pipeline);

        specularFlipper = new Flipper<Texture2D>(resources.texSpecular_A, resources.texSpecular_B);
        mainFlipper = new Flipper<Texture2D>(resources.mainTexture_A, resources.mainTexture_B);
        diffuseFlipper = new Flipper<Texture2D>(resources.texDiffuse_A, resources.texDiffuse_B);

        sky = new HillaireSky(pipeline);
        exposure = new Exposure(screen, pipeline);
        new Water(pipeline);

        if (settings.getBoolValue("Lighting_Accumulate")) {
            accumulation = new Accumulation(pipeline);
        }

        if (settings.getBoolValue("Froxels_Enabled")) {
            froxels = new Froxels(screen, pipeline);
        }

        // if (settings.getBoolValue("Sharc_Enabled")) {
            sharc = new Sharc(screen, pipeline);
        // }

        if (settings.getBoolValue("Bloom_Enabled")) {
            bloom = new Bloom(screen, pipeline);
        }

        withStage(pipeline, ProgramStage.PRE_RENDER, stage -> {
            sky.renderTransmit(stage);
            sky.renderMultiScatter(stage);
            sky.renderView(stage);

            stage.clearTo(new Vector4f(0f), resources.weatherTexture);
        });
        
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

        pipeline.object(ProgramUsage.WEATHER, "program/object/weather", "WeatherShader")
            .writes("color", resources.weatherTexture);
        
        withStage(pipeline, ProgramStage.POST_RENDER, stage -> {
            var sizeX_16 = (int)Math.ceil(screen.renderWidth() / 16f);
            var sizeY_16 = (int)Math.ceil(screen.renderHeight() / 16f);
            
            if (settings.getBoolValue("Sharc_Enabled")) {
                sharc.render(stage, diffuseFlipper.getWriter());
            }
            else {
                stage.compute("Deferred-Diffuse", "program/deferred/diffuse", "main")
                    .overrideObject("texDiffuse_write", diffuseFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);
            }

            diffuseFlipper.flip();
            
            if (settings.getBoolValue("SpecularEnabled")) {
                stage.compute("Deferred-Specular", "program/deferred/specular", "main")
                    .overrideObject("texSpecular_write", specularFlipper.getWriter().name())
                    .exportInt("SHARC_BUCKET_COUNT", sharc.bucketCount())
                    .dispatch2D(sizeX_16, sizeY_16);

                specularFlipper.flip();
            }

            if (settings.getBoolValue("Lighting_Accumulate")) {
                stage.compute("Deferred-Accumulate-Diffuse", "program/deferred/accumulate-diffuse", "main")
                    .overrideObject("texDiffuse_read", diffuseFlipper.getReader().name())
                    .overrideObject("texDiffuse_write", diffuseFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);

                diffuseFlipper.flip();

                stage.compute("Deferred-Accumulate-Specular", "program/deferred/accumulate-specular", "main")
                    .overrideObject("texSpecular_read", specularFlipper.getReader().name())
                    .overrideObject("texSpecular_write", specularFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);
                
                specularFlipper.flip();

                stage.compute("Deferred-Accumulate-Fill", "program/deferred/fill", "main")
                    .overrideObject("texDiffuse_read", diffuseFlipper.getReader().name())
                    .overrideObject("texDiffuse_write", diffuseFlipper.getWriter().name())
                    .overrideObject("texSpecular_read", specularFlipper.getReader().name())
                    .overrideObject("texSpecular_write", specularFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);

                diffuseFlipper.flip();
                specularFlipper.flip();
            }
            
            stage.compute("Deferred-Composite", "program/deferred/composite", "main")
                .overrideObject("texDiffuse_read", diffuseFlipper.getReader().name())
                .overrideObject("texSpecular_read", specularFlipper.getReader().name())
                .overrideObject("texMain_write", mainFlipper.getWriter().name())
                .exportInt("SHARC_BUCKET_COUNT", sharc.bucketCount())
                .dispatch2D(sizeX_16, sizeY_16);
            
            mainFlipper.flip();

            if (settings.getBoolValue("Volumetric_Enabled")) {
                if (froxels != null) froxels.render(stage);

                var volumetricShader = stage.compute("Volumetric", "program/deferred/volumetric", "main")
                    .overrideObject("texMain_read", mainFlipper.getReader().name())
                    .overrideObject("texMain_write", mainFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);
                
                if (froxels != null) {
                    volumetricShader
                        .exportInt("Froxel_Width", froxels.BufferWidth)
                        .exportInt("Froxel_Height", froxels.BufferHeight)
                        .exportInt("Froxel_Depth", froxels.BufferDepth);
                }

                mainFlipper.flip();
            }

            stage.generateMips(mainFlipper.getReader());

            stage.compute("Overlay", "program/deferred/overlay", "main")
                .overrideObject("texMain_read", mainFlipper.getReader().name())
                .overrideObject("texMain_write", mainFlipper.getWriter().name())
                .dispatch2D(sizeX_16, sizeY_16);

            mainFlipper.flip();

            if (settings.getBoolValue("TAA_Enabled")) {
                stage.compute("TAA", "program/post/taa", "main")
                    .overrideObject("texMain_read", mainFlipper.getReader().name())
                    .overrideObject("texMain_write", mainFlipper.getWriter().name())
                    .dispatch2D(sizeX_16, sizeY_16);

                mainFlipper.flip();
            }
        });

        withStage(pipeline, ProgramStage.POST_UPSCALE, stage -> {
            var sizeX_16 = (int)Math.ceil(screen.renderWidth() / 16f);
            var sizeY_16 = (int)Math.ceil(screen.renderHeight() / 16f);

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

            if (settings.getBoolValue("TAA_Enabled")) {
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
        // var settings = rendererConfig.getSettings();

        rendererConfig.enableRT();
        // rendererConfig.setShadowCascades(0);
    }

    @Override
	public void onNewFrame(FrameState state) {
        var rendererConfig = state.getRendererConfig();
        var settings = rendererConfig.getSettings();

        sky.Planet.SunAngularRadius = settings.getFloatValue("Sky_SunRadius");

        rendererConfig.setSunPathRotation(settings.getFloatValue("SunAngle"));

        sky.update();
        resources.update(state);
        if (froxels != null) froxels.update();
        if (accumulation != null) accumulation.update();
    }

    @Override
	public int setBlockId(IBlockState block) {
		return blocks.getId(block);
	}

    private void withStage(PipelineConfig pipeline, ProgramStage programStage, Consumer<StageList> callback) {
        callback.accept(pipeline.stage(programStage));
    }
}
