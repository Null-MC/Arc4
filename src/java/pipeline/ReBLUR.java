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
//
// Two kinds of buffers are used here, and they are NOT interchangeable:
//  - PingPongBuffer2D fields below are cross-frame HISTORY only. They are flipped
//    exactly once per frame in update() (called from onNewFrame), and must never be
//    read/written more than once within a single frame's render stages.
//  - Plain Texture2D fields are same-frame WORKING buffers: written once by one pass
//    and read once by a later pass within the same frame, with no ping-pong at all.
public class ReBLUR {
    private final Screen screen;

    private final PingPongBuffer2D colorHistory;
    private final PingPongBuffer2D dataHistory;
    private final PingPongBuffer2D depthHistory;
    private final PingPongBuffer2D stableHistory;

    private final Texture2D texAccumColor;
    private final Texture2D texAccumData;
    private final Texture2D texBlur;
    private final Texture2D texPostBlur;
    private final Texture2D texFinal;


    public ReBLUR(Screen screen, PipelineConfig pipeline) {
        this.screen = screen;

        colorHistory = new PingPongBufferBuilder2D(pipeline, "texReblurColorHistory", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();

        // r = luminance moment 1, g = luminance moment 2, b = accumulated frame count, a = accumulated hit distance.
        dataHistory = new PingPongBufferBuilder2D(pipeline, "texReblurDataHistory", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();

        depthHistory = new PingPongBufferBuilder2D(pipeline, "texReblurDepthHistory", TextureFormat.R32_SFLOAT)
            .renderSize()
            .createEmpty();

        stableHistory = new PingPongBufferBuilder2D(pipeline, "texReblurStableHistory", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .createEmpty();

        texAccumColor = pipeline.texture2D("texReblurAccumColor", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        texAccumData = pipeline.texture2D("texReblurAccumData", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        texBlur = pipeline.texture2D("texReblurBlur", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        texPostBlur = pipeline.texture2D("texReblurPostBlur", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();

        texFinal = pipeline.texture2D("texReblurFinal", TextureFormat.RGBA16_SFLOAT)
            .renderSize()
            .create();
    }

    // Advances the cross-frame history buffers. Call exactly once per frame, before render().
    public void update() {
        colorHistory.flip();
        dataHistory.flip();
        depthHistory.flip();
        stableHistory.flip();
    }

    // rawDiffuseReaderName: this frame's raw noisy diffuse signal (rgb = color, a = normalized hit distance).
    public void render(StageList stage, String rawDiffuseReaderName) {
        var sizeX_16 = (int)Math.ceil(screen.renderWidth() / 16f);
        var sizeY_16 = (int)Math.ceil(screen.renderHeight() / 16f);

        stage.compute("ReBLUR-Temporal", "program/deferred/reblur/temporal", "main")
            .overrideObject("texDiffuse_read", rawDiffuseReaderName)
            .overrideObject("texAccumColor_write", texAccumColor.name())
            .overrideObject("texAccumData_write", texAccumData.name())
            .dispatch2D(sizeX_16, sizeY_16);

        stage.compute("ReBLUR-Blur", "program/deferred/reblur/blur", "main")
            .overrideObject("texAccumColor_read", texAccumColor.name())
            .overrideObject("texAccumData_read", texAccumData.name())
            .overrideObject("texBlur_write", texBlur.name())
            .dispatch2D(sizeX_16, sizeY_16);

        stage.compute("ReBLUR-PostBlur", "program/deferred/reblur/postblur", "main")
            .overrideObject("texBlur_read", texBlur.name())
            .overrideObject("texAccumData_read", texAccumData.name())
            .overrideObject("texPostBlur_write", texPostBlur.name())
            .dispatch2D(sizeX_16, sizeY_16);

        stage.compute("ReBLUR-Stabilize", "program/deferred/reblur/stabilize", "main")
            .overrideObject("texPostBlur_read", texPostBlur.name())
            .overrideObject("texAccumData_read", texAccumData.name())
            .overrideObject("texFinal_write", texFinal.name())
            .dispatch2D(sizeX_16, sizeY_16);
    }

    public String resultName() {
        return texFinal.name();
    }
}

