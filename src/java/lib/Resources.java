package lib;

import buffers.PlanetBuffer;
import buffers.SceneBuffer;
import buffers.SkyBuffer;

import dev.irisshaders.aperture.api.objects.AddressMode;
import dev.irisshaders.aperture.api.objects.FilterMode;
import dev.irisshaders.aperture.api.objects.MappedBuffer;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.FrameState;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class Resources {
    private Screen screen;

    public final Texture2D texOpaqueColor;
    public final Texture2D texOpaqueNormal;
    public final Texture2D texOpaqueSpecular;

    public final Texture2D texDiffuse_A;
    public final Texture2D texDiffuse_B;

    public final Texture2D mainTexture_A;
    public final Texture2D mainTexture_B;

    public final MappedBuffer<SceneBuffer> bufferScene;

    public PingPongBuffer2D diffuseHistory;
    public PingPongBuffer2D taaHistory;
    

    public Resources(Screen screen, PipelineConfig pipeline) {
        this.screen = screen;

        pipeline.loadPNGTexture("blueNoiseTexture", "assets/blue_noise_64.png");

        pipeline.sampler("blueNoiseSampler")
            .addressMode(AddressMode.REPEAT)
            .minFilter(FilterMode.NEAREST)
            .magFilter(FilterMode.NEAREST)
            .create();

        texOpaqueColor = pipeline.texture2D("texOpaqueColor", TextureFormat.RGBA8_UNORM)
            .renderSize()
            .create();

        texOpaqueNormal = pipeline.texture2D("texOpaqueNormal", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        texOpaqueSpecular = pipeline.texture2D("texOpaqueSpecular", TextureFormat.RGBA8_UNORM)
            .renderSize()
            .create();

        texDiffuse_A = pipeline.texture2D("texDiffuse_A", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        texDiffuse_B = pipeline.texture2D("texDiffuse_B", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        pipeline.texture1D("texHistogram", TextureFormat.R32_UINT)
            .size(256)
            .create();

        if (pipeline.settings().getBoolValue("Accumulation")) {
            diffuseHistory = new PingPongBufferBuilder2D(pipeline, "texDiffuseHistory", TextureFormat.RGBA16_SFLOAT)
                .renderSize()
                .createEmpty();
        }

        mainTexture_A = pipeline.texture2D("mainTexture_A", TextureFormat.RGBA16_SFLOAT)
            .windowSize()
            .create();
        
        mainTexture_B = pipeline.texture2D("mainTexture_B", TextureFormat.RGBA16_SFLOAT)
            .windowSize()
            .create();

        if (pipeline.settings().getBoolValue("TAA_Enabled")) {
            taaHistory = new PingPongBufferBuilder2D(pipeline, "texTaaHistory", TextureFormat.RGBA16_SFLOAT)
                .windowSize()
                .createEmpty();
        }

        bufferScene = pipeline.mappedBuffer("scene", SceneBuffer.class);

        var bufferPlanet = pipeline.mappedBuffer("planet", PlanetBuffer.class);
        bufferPlanet.write(PlanetBuffer.Earth);

        var bufferSky = pipeline.mappedBuffer("sky", SkyBuffer.class);
        bufferSky.write(SkyBuffer.Earth);

        pipeline.buffer("exposure", 4);
    }

    public void update(FrameState state) {
        bufferScene.write(SceneBuffer.Build(state, screen));
        
        if (diffuseHistory != null) diffuseHistory.flip();
        if (taaHistory != null) taaHistory.flip();
    }
}
