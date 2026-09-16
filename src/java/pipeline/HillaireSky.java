package pipeline;

import buffers.PlanetBuffer;
import buffers.SkyBuffer;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.AddressMode;
import dev.irisshaders.aperture.api.objects.FilterMode;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;


public class HillaireSky {
    public final int TransmitBufferWidth = 256;
    public final int TransmitBufferHeight = 64;
    public final Texture2D TransmitTexture;

    public final int MultiScatterBufferWidth = 32;
    public final int MultiScatterBufferHeight = 32;
    public final Texture2D MultiScatterTexture;

    public final int ViewBufferWidth = 256;
    public final int ViewBufferHeight = 256;
    public final Texture2D ViewTexture;


    public HillaireSky(PipelineConfig pipeline) {
        TransmitTexture = pipeline.texture2D("texSkyTransmit", TextureFormat.RGBA16_UNORM)
            .size(TransmitBufferWidth, TransmitBufferHeight)
            .create();
        
        MultiScatterTexture = pipeline.texture2D("texSkyMultiScatter", TextureFormat.RGBA16_SFLOAT)
            .size(MultiScatterBufferWidth, MultiScatterBufferHeight)
            .create();

        ViewTexture = pipeline.texture2D("texSkyView", TextureFormat.RGBA16_SFLOAT)
            .size(ViewBufferWidth, ViewBufferHeight)
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

        var bufferPlanet = pipeline.mappedBuffer("planet", PlanetBuffer.class);
        bufferPlanet.write(PlanetBuffer.Earth);

        var bufferSky = pipeline.mappedBuffer("sky", SkyBuffer.class);
        bufferSky.write(SkyBuffer.Earth);
    }

    public void renderTransmit(StageList stage) {
        var sizeX = (int)Math.ceil(TransmitBufferWidth / 16f);
        var sizeY = (int)Math.ceil(TransmitBufferHeight / 16f);

        stage.compute("sky-transmit", "program/pre/sky-transmit", "main")
            .exportInt("BufferWidth", TransmitBufferWidth)
            .exportInt("BufferHeight", TransmitBufferHeight)
            .dispatch2D(sizeX, sizeY);
    }

    public void renderMultiScatter(StageList stage) {
        var sizeX = (int)Math.ceil(MultiScatterBufferWidth / 16f);
        var sizeY = (int)Math.ceil(MultiScatterBufferHeight / 16f);

        stage.compute("sky-multiscatter", "program/pre/sky-multiscatter", "main")
            .exportInt("BufferWidth", MultiScatterBufferWidth)
            .exportInt("BufferHeight", MultiScatterBufferHeight)
            .dispatch2D(sizeX, sizeY);
    }

    public void renderView(StageList stage) {
        var sizeX = (int)Math.ceil(ViewBufferWidth / 16f);
        var sizeY = (int)Math.ceil(ViewBufferHeight / 16f);

        stage.compute("sky-view", "program/pre/sky-view", "main")
            .exportInt("BufferWidth", ViewBufferWidth)
            .exportInt("BufferHeight", ViewBufferHeight)
            .dispatch2D(sizeX, sizeY);
    }
}
