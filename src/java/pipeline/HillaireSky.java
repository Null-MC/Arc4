package pipeline;

import dev.irisshaders.aperture.api.commands.ComputeCommand;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.AddressMode;
import dev.irisshaders.aperture.api.objects.FilterMode;
import dev.irisshaders.aperture.api.objects.MappedBuffer;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

import buffers.PlanetBuffer;
import buffers.SkyBuffer;
import lib.PlanetData;
import lib.Shader.ShaderBuilder;


public class HillaireSky {
    public PlanetData Planet;
    public SkyBuffer Sky;

    private final MappedBuffer<PlanetBuffer> planetBuffer;
    private final MappedBuffer<SkyBuffer> skyBuffer;

    public final int TransmitBufferWidth = 256;
    public final int TransmitBufferHeight = 64;
    public final Texture2D TransmitTexture;

    public final int MultiScatterBufferWidth = 32;
    public final int MultiScatterBufferHeight = 32;
    public final Texture2D MultiScatterTexture;

    public final int ViewBufferWidth = 256;
    public final int ViewBufferHeight = 256;
    public final Texture2D ViewTexture;
    public final Texture2D ViewCloudTexture;

    public final int DeferCloudBufferWidth;
    public final int DeferCloudBufferHeight;
    public final Texture2D DeferCloudTexture;


    public HillaireSky(Screen screen, PipelineConfig pipeline) {
        Planet = new PlanetData();
        Planet.RadiusGround_KM = 3_360.f;
        Planet.RadiusAtmosphere_KM = 3_460.f;
        Planet.SunAngularRadius = 0.00931f;

        Sky = SkyBuffer.Earth;

        DeferCloudBufferWidth = (int)Math.ceil(screen.renderWidth() / 4.0);
        DeferCloudBufferHeight = (int)Math.ceil(screen.renderHeight() / 4.0);

        pipeline.loadPNGTexture("texCloudNoise", "assets/cloud-noise.png");

        TransmitTexture = pipeline.texture2D("texSkyTransmit", TextureFormat.RGBA16_UNORM)
            .size(TransmitBufferWidth, TransmitBufferHeight)
            .create();
        
        MultiScatterTexture = pipeline.texture2D("texSkyMultiScatter", TextureFormat.RGBA16_SFLOAT)
            .size(MultiScatterBufferWidth, MultiScatterBufferHeight)
            .create();

        ViewTexture = pipeline.texture2D("texSkyView", TextureFormat.RGBA16_SFLOAT)
            .size(ViewBufferWidth, ViewBufferHeight)
            .create();

        ViewCloudTexture = pipeline.texture2D("texSkyViewClouds", TextureFormat.RGBA16_SFLOAT)
            .size(ViewBufferWidth, ViewBufferHeight)
            .create();

        DeferCloudTexture = pipeline.texture2D("texDeferClouds", TextureFormat.RGBA16_SFLOAT)
            .size(DeferCloudBufferWidth, DeferCloudBufferHeight)
            .create();

        pipeline.sampler("skyTransmitSampler")
            .addressMode(AddressMode.CLAMP)
            .minFilter(FilterMode.LINEAR)
            .magFilter(FilterMode.LINEAR)
            .create();
        
        pipeline.sampler("skyMultiScatterSampler")
            .addressMode(AddressMode.CLAMP)
            .minFilter(FilterMode.LINEAR)
            .magFilter(FilterMode.LINEAR)
            .create();
        
        pipeline.sampler("skyViewSampler")
            .addressModeX(AddressMode.REPEAT)
            .addressModeY(AddressMode.CLAMP)
            .minFilter(FilterMode.LINEAR)
            .magFilter(FilterMode.LINEAR)
            .create();

        planetBuffer = pipeline.mappedBuffer("planet", PlanetBuffer.class);
        skyBuffer = pipeline.mappedBuffer("sky", SkyBuffer.class);
    }

    public void update() {
        planetBuffer.write(Planet.ToBuffer());
        skyBuffer.write(Sky);
    }

    public ComputeCommand renderTransmit(StageList stage, ShaderBuilder builder) {
        return builder.compute(stage, "sky-transmit", "program/pre/sky-transmit", shader -> shader
            .exportInt("BufferWidth", TransmitBufferWidth)
            .exportInt("BufferHeight", TransmitBufferHeight)
            .dispatch2D(TransmitBufferWidth, TransmitBufferHeight, 16, 16));
    }

    public ComputeCommand renderMultiScatter(StageList stage, ShaderBuilder builder) {
        return builder.compute(stage, "sky-multiscatter", "program/pre/sky-multiscatter", shader -> shader
            .exportInt("BufferWidth", MultiScatterBufferWidth)
            .exportInt("BufferHeight", MultiScatterBufferHeight)
            .dispatch2D(MultiScatterBufferWidth, MultiScatterBufferHeight, 16, 16));
    }

    public ComputeCommand renderView(StageList stage, ShaderBuilder builder) {
        return builder.compute(stage, "sky-view", "program/pre/sky-view", shader -> shader
            .exportInt("BufferWidth", ViewBufferWidth)
            .exportInt("BufferHeight", ViewBufferHeight)
            .dispatch2D(ViewBufferWidth, ViewBufferHeight, 16, 16));
    }

    public ComputeCommand renderClouds(StageList stage, ShaderBuilder builder) {
        return builder.compute(stage, "Deferred-Clouds", "program/deferred/clouds", shader -> shader
            .exportInt("BufferWidth", DeferCloudBufferWidth)
            .exportInt("BufferHeight", DeferCloudBufferHeight)
            .dispatch2D(DeferCloudBufferWidth, DeferCloudBufferHeight, 16, 16));
    }
}
