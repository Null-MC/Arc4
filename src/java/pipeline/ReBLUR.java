package pipeline;

import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

import lib.PingPongBuffer2D;
import lib.PingPongBufferBuilder2D;

// A ReBLUR-inspired spatiotemporal denoiser for the diffuse GI signal: temporal
// accumulation with hit-distance/variance tracking, two adaptive-radius spatial
// blur passes, then a temporal stabilization pass to suppress residual flicker.
public class ReBLUR {
    private final Screen screen;

    private final PingPongBuffer2D rawSignal;
    private final PingPongBuffer2D accumColor;
    private final PingPongBuffer2D accumData;
    private final PingPongBuffer2D depthHistory;
    private final PingPongBuffer2D stableHistory;

    private final Texture2D texBlur;
    private final Texture2D texPostBlur;


    public ReBLUR(Screen screen, PipelineConfig pipeline) {
        this.screen = screen;

        // Raw noisy signal written by the diffuse GI pass each frame: rgb = color, a = normalized hit distance.
        rawSignal = new PingPongBufferBuilder2D(pipeline, "texDiffuse", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();

        accumColor = new PingPongBufferBuilder2D(pipeline, "texReblurColor", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();

        // r = luminance moment 1, g = luminance moment 2, b = accumulated frame count, a = accumulated hit distance.
        accumData = new PingPongBufferBuilder2D(pipeline, "texReblurData", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();

        depthHistory = new PingPongBufferBuilder2D(pipeline, "texReblurDepth", TextureFormat.R32_SFLOAT)
            .renderSize()
            .createEmpty();

        stableHistory = new PingPongBufferBuilder2D(pipeline, "texReblurStable", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();

        texBlur = pipeline.texture2D("texReblurBlur", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        texPostBlur = pipeline.texture2D("texReblurPostBlur", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();
    }

    public void render(StageList stage) {
        // The raw signal was just written this frame under the "write" slot; flip so
        // the temporal pass can read it back through the fixed "_read" reference.
        rawSignal.flip();

        var sizeX_16 = (int)Math.ceil(screen.renderWidth() / 16f);
        var sizeY_16 = (int)Math.ceil(screen.renderHeight() / 16f);

        stage.compute("ReBLUR-Temporal", "program/deferred/reblur-temporal", "main")
            .dispatch2D(sizeX_16, sizeY_16);

        accumColor.flip();
        accumData.flip();
        depthHistory.flip();

        stage.compute("ReBLUR-Blur", "program/deferred/reblur-blur", "main")
            .overrideObject("texBlur_write", texBlur.name())
            .dispatch2D(sizeX_16, sizeY_16);

        stage.compute("ReBLUR-PostBlur", "program/deferred/reblur-postblur", "main")
            .overrideObject("texBlur_read", texBlur.name())
            .overrideObject("texPostBlur_write", texPostBlur.name())
            .dispatch2D(sizeX_16, sizeY_16);

        stage.compute("ReBLUR-Stabilize", "program/deferred/reblur-stabilize", "main")
            .overrideObject("texPostBlur_read", texPostBlur.name())
            .dispatch2D(sizeX_16, sizeY_16);

        stableHistory.flip();
    }
}
