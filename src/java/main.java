import java.util.function.Consumer;

import org.joml.Vector4f;

import dev.irisshaders.aperture.api.*;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.*;
import dev.irisshaders.aperture.api.pipeline.*;
import dev.irisshaders.aperture.api.renderer.*;

import pipeline.Froxels;
import pipeline.LightList;
import pipeline.Bloom;
import pipeline.Exposure;
import pipeline.HillaireSky;
import pipeline.Resources;
import pipeline.Sharc;
import pipeline.Water;
import pipeline.Accumulation;
import lib.Flipper;
import lib.Shader.ShaderBuilder;


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
    private Flipper<Texture2D> diffuseFastFlipper;
    private Flipper<Texture2D> specularFlipper;

    private ShaderBuilder builder;


    @Override
	public void configurePipeline(Screen screen, PipelineConfig pipeline) {
        var settings = pipeline.settings();
        resources = new Resources(screen, pipeline);

        builder = new ShaderBuilder(screen, pipeline);
        blocks.map(builder);

        specularFlipper = new Flipper<Texture2D>(resources.texSpecular_A, resources.texSpecular_B);
        mainFlipper = new Flipper<Texture2D>(resources.mainTexture_A, resources.mainTexture_B);
        diffuseFlipper = new Flipper<Texture2D>(resources.texDiffuse_A, resources.texDiffuse_B);
        diffuseFastFlipper = new Flipper<Texture2D>(resources.texDiffuseFast_A, resources.texDiffuseFast_B);

        sky = new HillaireSky(screen, pipeline);
        exposure = new Exposure(screen, pipeline);
        new Water(pipeline);

        if (settings.getBoolValue("Lighting_Accumulate")) {
            accumulation = new Accumulation(pipeline);
        }

        if (settings.getBoolValue("Froxels_Enabled")) {
            froxels = new Froxels(screen, pipeline, builder);

            builder
                .exportInt("Froxel_Width", froxels.BufferWidth)
                .exportInt("Froxel_Height", froxels.BufferHeight)
                .exportInt("Froxel_Depth", froxels.BufferDepth);
        }

        // if (settings.getBoolValue("Sharc_Enabled")) {
            sharc = new Sharc(screen, pipeline);

            builder.exportInt("SHARC_BUCKET_COUNT", sharc.bucketCount());
        // }

        if (settings.getBoolValue("Bloom_Enabled")) {
            bloom = new Bloom(screen, pipeline);
        }

        var lightList = new LightList(pipeline, builder);

        withStage(pipeline, ProgramStage.PRE_RENDER, stage -> {
            sky.renderTransmit(stage, builder);
            sky.renderMultiScatter(stage, builder);
            sky.renderView(stage, builder);

            stage.clearTo(new Vector4f(0f), resources.weatherTexture);

            lightList.render(stage, builder);
        });
        
        builder.discard(ProgramUsage.SKYBOX);
        builder.discard(ProgramUsage.SKY_TEXTURES);
        builder.discard(ProgramUsage.CLOUDS);

        builder.object(ProgramUsage.BASIC, "program/object/defer", shader -> shader
            .writes("color", resources.texDeferColor, BlendMode.NONE)
            .writes("normal", resources.texDeferNormal, BlendMode.NONE)
            .writes("specular", resources.texDeferSpecular, BlendMode.NONE)
            .writes("data", resources.texDeferData, BlendMode.NONE));

        builder.object(ProgramUsage.TRANSLUCENT, "program/object/defer", shader -> shader
            .writes("color", resources.texDeferColor, BlendMode.NONE)
            .writes("normal", resources.texDeferNormal, BlendMode.NONE)
            .writes("specular", resources.texDeferSpecular, BlendMode.NONE)
            .writes("data", resources.texDeferData, BlendMode.NONE)
            .exportBool("IsTranslucent", true));

        builder.object(ProgramUsage.PARTICLES, "program/object/defer-particle", shader -> shader
            .writes("color", resources.texDeferColor, BlendMode.NONE)
            .writes("normal", resources.texDeferNormal, BlendMode.NONE)
            .writes("specular", resources.texDeferSpecular, BlendMode.NONE)
            .writes("data", resources.texDeferData, BlendMode.NONE));

        builder.object(ProgramUsage.PARTICLES_TRANSLUCENT, "program/object/defer-particle", shader -> shader
            .writes("color", resources.texDeferColor, BlendMode.NONE)
            .writes("normal", resources.texDeferNormal, BlendMode.NONE)
            .writes("specular", resources.texDeferSpecular, BlendMode.NONE)
            .writes("data", resources.texDeferData, BlendMode.NONE)
            .exportBool("IsTranslucent", true));

        builder.object(ProgramUsage.WEATHER, "program/object/weather", shader -> shader
            .writes("color", resources.weatherTexture));
        
        withStage(pipeline, ProgramStage.POST_RENDER, stage -> {
            if (settings.getBoolValue("Sharc_Enabled")) {
                sharc.render(stage, builder, diffuseFlipper.getWriter());
            }
            else {
                builder.compute(stage, "Deferred-Diffuse", "program/deferred/diffuse", shader -> {
                    shader.override("texDiffuse_write", diffuseFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                });
            }

            diffuseFlipper.flip();
            
            if (settings.getBoolValue("SpecularEnabled")) {
                builder.compute(stage, "Deferred-Specular-Refract", "program/deferred/refraction", shader -> {
                    shader.override("texSpecular_write", specularFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                });

                specularFlipper.flip();

                builder.compute(stage, "Deferred-Specular-Reflect", "program/deferred/reflection", shader -> {
                    shader.override("texSpecular_read", specularFlipper.getReader());
                    shader.override("texSpecular_write", specularFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                });

                specularFlipper.flip();

                // stage.compute("Deferred-Specular", "program/deferred/specular", "main")
                //     .overrideObject("texSpecular_write", specularFlipper.getWriter().name())
                //     .exportInt("SHARC_BUCKET_COUNT", sharc.bucketCount())
                //     .dispatch2D(sizeX_16, sizeY_16);

                // specularFlipper.flip();
            }

            if (settings.getBoolValue("Lighting_Accumulate")) {
                builder.compute(stage, "Deferred-Accumulate-Diffuse", "program/deferred/accumulate-diffuse", shader -> {
                    shader.override("texDiffuse_read", diffuseFlipper.getReader());
                    shader.override("texDiffuse_write", diffuseFlipper.getWriter());
                    shader.override("texDiffuseFast_write", diffuseFastFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                });

                diffuseFlipper.flip();
                diffuseFastFlipper.flip();

                builder.compute(stage, "Deferred-Accumulate-Specular", "program/deferred/accumulate-specular", shader -> {
                    shader.override("texSpecular_read", specularFlipper.getReader());
                    shader.override("texSpecular_write", specularFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                });
                
                specularFlipper.flip();

                builder.compute(stage, "Deferred-Accumulate-Fill", "program/deferred/accumulate-fill", shader -> {
                    shader.override("texDiffuse_read", diffuseFlipper.getReader());
                    shader.override("texDiffuse_write", diffuseFlipper.getWriter());
                    shader.override("texDiffuseFast_read", diffuseFastFlipper.getReader());
                    shader.override("texSpecular_read", specularFlipper.getReader());
                    shader.override("texSpecular_write", specularFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                });

                diffuseFlipper.flip();
                specularFlipper.flip();
            }
            
            for (int i = 0; i < settings.getIntValue("Lighting_BlurLevel"); i++) {
                int aTrousLevel = i;
                builder.compute(stage, "Deferred-Diffuse-Blur"+i, "program/deferred/diffuse-blur", shader -> {
                    shader.override("texDiffuse_read", diffuseFlipper.getReader());
                    shader.override("texDiffuse_write", diffuseFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                    shader.exportInt("ATrousLevel", aTrousLevel);
                });

                diffuseFlipper.flip();

                if (settings.getBoolValue("SpecularEnabled")) {
                    builder.compute(stage, "Deferred-Specular-Blur"+i, "program/deferred/specular-blur", shader -> {
                        shader.override("texSpecular_read", specularFlipper.getReader());
                        shader.override("texSpecular_write", specularFlipper.getWriter());
                        shader.dispatchRenderSize(16, 16);
                        shader.exportInt("ATrousLevel", aTrousLevel);
                    });

                    specularFlipper.flip();
                }
            }
            
            builder.compute(stage, "Deferred-Diffuse-Hand", "program/deferred/diffuse-hand", shader -> {
                shader.override("texDiffuse_read", diffuseFlipper.getReader());
                shader.override("texDiffuse_write", diffuseFlipper.getWriter());
                shader.dispatchRenderSize(16, 16);
            });

            diffuseFlipper.flip();

            sky.renderClouds(stage, builder);

            builder.compute(stage, "Deferred-Composite", "program/deferred/composite", shader -> {
                shader.override("texDiffuse_read", diffuseFlipper.getReader());
                shader.override("texSpecular_read", specularFlipper.getReader());
                shader.override("texMain_write", mainFlipper.getWriter());
                shader.dispatchRenderSize(16, 16);
            });
            
            mainFlipper.flip();

            if (settings.getBoolValue("Volumetric_Enabled")) {
                if (froxels != null) froxels.render(stage, builder);
                
                builder.compute(stage, "Volumetric", "program/deferred/volumetric", shader -> {
                    shader.override("texMain_read", mainFlipper.getReader());
                    shader.override("texMain_write", mainFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                });

                mainFlipper.flip();
            }

            stage.generateMips(mainFlipper.getReader());

            builder.compute(stage, "Overlay", "program/deferred/overlay", shader -> {
                shader.override("texMain_read", mainFlipper.getReader());
                shader.override("texMain_write", mainFlipper.getWriter());
                shader.dispatchRenderSize(16, 16);
            });

            mainFlipper.flip();

            if (settings.getBoolValue("TAA_Enabled")) {
                builder.compute(stage, "TAA", "program/post/taa", shader -> {
                    shader.override("texMain_read", mainFlipper.getReader());
                    shader.override("texMain_write", mainFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                });

                mainFlipper.flip();
            }
        });

        withStage(pipeline, ProgramStage.POST_UPSCALE, stage -> {
            if (bloom != null) {
                bloom.render(stage, mainFlipper.getReader());
                // do not flip, writes to reader!
            }

            exposure.render(stage, mainFlipper.getReader());
            
            builder.compute(stage, "Tonemap", "program/post/tonemap", shader -> {
                shader.override("tex_read", mainFlipper.getReader());
                shader.override("tex_write", mainFlipper.getWriter());
                shader.dispatchRenderSize(16, 16);
            });

            mainFlipper.flip();

            if (settings.getBoolValue("TAA_Enabled")) {
                // TAA CAS Sharpening
                builder.compute(stage, "Sharpen", "program/post/sharpen", shader -> {
                    shader.override("texMain_read", mainFlipper.getReader());
                    shader.override("texMain_write", mainFlipper.getWriter());
                    shader.dispatchRenderSize(16, 16);
                });

                mainFlipper.flip();
            }
        });

        pipeline.combinationPass("program/post/final")
            .overrideObject("tex_read", mainFlipper.getReader().name());

        builder.updateLights();
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

        sky.Planet.RadiusGround_KM = settings.getFloatValue("Planet_GroundRadius");
        sky.Planet.RadiusAtmosphere_KM = settings.getFloatValue("Planet_AtmosphereRadius");

        sky.Planet.SunAngularRadius = settings.getFloatValue("Sky_SunRadius");
        sky.Planet.MoonAngularRadius = settings.getFloatValue("Sky_MoonRadius");

        rendererConfig.setSunPathRotation(settings.getFloatValue("SunAngle"));

        sky.update();
        resources.update(state);
        if (froxels != null) froxels.update();
        if (accumulation != null) accumulation.update();
    }

    @Override
	public int setBlockId(IBlockState block) {
		return builder.getBlockId(block);
	}

    private void withStage(PipelineConfig pipeline, ProgramStage programStage, Consumer<StageList> callback) {
        callback.accept(pipeline.stage(programStage));
    }
}
