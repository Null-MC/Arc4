package pipeline;

import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class Bloom {
    private final Texture2D texBloom;
    private int maxLod;

    
    public Bloom(Screen screen, PipelineConfig pipeline) {
        var sizeX = (int)Math.ceil(screen.windowWidth() / 2f);
        var sizeY = (int)Math.ceil(screen.windowHeight() / 2f);

        double lodF = log2(Math.min(screen.windowWidth(), screen.windowHeight()));
        maxLod = (int)Math.floor(lodF) - 1;

        // clamp final dimensions
        maxLod = Math.clamp(maxLod, 0, 8);

        texBloom = pipeline.texture2D("texBloom", TextureFormat.RGBA16_SFLOAT)
            .size(sizeX, sizeY)
            .usesMipmaps()
            .create();
    }

    public void render(StageList stage, Texture2D texMain_read) {
        for (int i = 0; i < maxLod; i++) {
            stage.composite("bloom-down-"+i, "program/post/bloom", "bloomDown")
                .overrideObject("tex_read", i == 0 ? texMain_read.name() : "texBloom")
                .exportInt("mip_read", Math.max(i-1, 0))
                .exportInt("mip_write", i)
                .writes("color", texBloom, i);
        }

        for (int i = maxLod-1; i >= 0; i--) {
            var bloomUpShader = stage.composite("bloom-up-"+i, "program/post/bloom", "bloomUp")
                .overrideObject("tex_read", "texBloom")
                .exportInt("mip_read", i)
                .exportInt("mip_write", Math.max(i-1, 0))
                .exportInt("tile_index", i);
            
            if (i == 0) {
                bloomUpShader
                    .overrideObject("tex_write", texMain_read.name())
                    .writes("color", texMain_read);
                    // .blendFunc(0, Func.ONE, Func.ZERO, Func.ONE, Func.ZERO);
            }
            else {
                bloomUpShader
                    .overrideObject("tex_write", "texBloom")
                    .writes("color", texBloom, i-1);
                    // .blendFunc(0, Func.ONE, Func.ONE, Func.ONE, Func.ONE);
            }
        }
    }

    private static double log2(double x) {
        return Math.log(x) / Math.log(2);
    }
}
