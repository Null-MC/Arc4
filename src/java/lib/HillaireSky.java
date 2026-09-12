package lib;

import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.AddressMode;
import dev.irisshaders.aperture.api.objects.FilterMode;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;


public class HillaireSky {
    public int TransmitBufferWidth = 256;
    public int TransmitBufferHeight = 64;
    public Texture2D TransmitTexture;

    public int MultiScatterBufferWidth = 32;
    public int MultiScatterBufferHeight = 32;
    public Texture2D MultiScatterTexture;

    public int ViewBufferWidth = 256;
    public int ViewBufferHeight = 256;
    public Texture2D ViewTexture;


    public void Initialize(PipelineConfig pipeline) {
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
            .addressMode(AddressMode.REPEAT)
            .minFilter(FilterMode.LINEAR)
            .magFilter(FilterMode.LINEAR)
            .create();
    }

    public void renderTransmit(StageList stage) {
        var sizeX = (int)Math.ceil(TransmitBufferWidth / 16f);
        var sizeY = (int)Math.ceil(TransmitBufferHeight / 16f);

        stage.compute("sky-transmit", "pre/sky-transmit", "main")
            .exportInt("BufferWidth", TransmitBufferWidth)
            .exportInt("BufferHeight", TransmitBufferHeight)
            .dispatch2D(sizeX, sizeY);
    }

    public void renderMultiScatter(StageList stage) {
        var sizeX = (int)Math.ceil(MultiScatterBufferWidth / 16f);
        var sizeY = (int)Math.ceil(MultiScatterBufferHeight / 16f);

        stage.compute("sky-multiscatter", "pre/sky-multiscatter", "main")
            .exportInt("BufferWidth", MultiScatterBufferWidth)
            .exportInt("BufferHeight", MultiScatterBufferHeight)
            .dispatch2D(sizeX, sizeY);
    }

    public void renderView(StageList stage) {
        var sizeX = (int)Math.ceil(ViewBufferWidth / 16f);
        var sizeY = (int)Math.ceil(ViewBufferHeight / 16f);

        stage.compute("sky-view", "pre/sky-view", "main")
            .exportInt("BufferWidth", ViewBufferWidth)
            .exportInt("BufferHeight", ViewBufferHeight)
            .dispatch2D(sizeX, sizeY);
    }
}
