package pipeline;

import buffers.SceneBuffer;

import dev.irisshaders.aperture.api.objects.AddressMode;
import dev.irisshaders.aperture.api.objects.FilterMode;
import dev.irisshaders.aperture.api.objects.MappedBuffer;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.FrameState;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

import lib.PingPongBuffer2D;
import lib.PingPongBufferBuilder2D;

public class Resources {
    private Screen screen;

    public final Texture2D texDeferColor;
    public final Texture2D texDeferNormal;
    public final Texture2D texDeferSpecular;
    public final Texture2D texDeferData;

    public final Texture2D texSpecular_A;
    public final Texture2D texSpecular_B;

    public final Texture2D mainTexture_A;
    public final Texture2D mainTexture_B;

    public final MappedBuffer<SceneBuffer> bufferScene;

    public PingPongBuffer2D taaHistory;
    

    public Resources(Screen screen, PipelineConfig pipeline) {
        this.screen = screen;

        pipeline.loadPNGTexture("blueNoiseTexture", "assets/blue_noise_64.png");

        pipeline.sampler("blueNoiseSampler")
            .addressMode(AddressMode.REPEAT)
            .minFilter(FilterMode.NEAREST)
            .magFilter(FilterMode.NEAREST)
            .create();

        texDeferColor = pipeline.texture2D("texDeferColor", TextureFormat.RGBA8_UNORM)
            .renderSize()
            .create();

        texDeferNormal = pipeline.texture2D("texDeferNormal", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        texDeferSpecular = pipeline.texture2D("texDeferSpecular", TextureFormat.RGBA8_UNORM)
            .renderSize()
            .create();

        texDeferData = pipeline.texture2D("texDeferData", TextureFormat.RG16_UINT)
            .renderSize()
            .create();

        texSpecular_A = pipeline.texture2D("texSpecular_A", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        texSpecular_B = pipeline.texture2D("texSpecular_B", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        mainTexture_A = pipeline.texture2D("mainTexture_A", TextureFormat.RGBA16_SFLOAT)
            .windowSize()
            .create();
        
        mainTexture_B = pipeline.texture2D("mainTexture_B", TextureFormat.RGBA16_SFLOAT)
            .windowSize()
            .create();

        if (pipeline.settings().getBoolValue("TAA_Enabled")) {
            taaHistory = new PingPongBufferBuilder2D(pipeline, "texTaaHistory", TextureFormat.RGBA32_SFLOAT)
                .windowSize()
                .createEmpty();
        }

        bufferScene = pipeline.mappedBuffer("scene", SceneBuffer.class);
    }

    public void update(FrameState state) {
        bufferScene.write(SceneBuffer.Build(state, screen));
        
        if (taaHistory != null) taaHistory.flip();
    }
}
