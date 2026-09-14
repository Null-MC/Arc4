package lib;

import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.AddressMode;
import dev.irisshaders.aperture.api.objects.FilterMode;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture3D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.objects.TextureReference3D;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class Froxels {
    private final Flipper<Texture3D> flipper;
    private final TextureReference3D reader;
    private final TextureReference3D writer;

    public int BufferWidth;
    public int BufferHeight;
    public int BufferDepth;

    
    public Froxels(PipelineConfig pipeline, Screen screen) {
        BufferWidth = (int)Math.ceil(screen.renderWidth() / 8f);
        BufferHeight = (int)Math.ceil(screen.renderHeight() / 8f);
        BufferDepth = 64;

        var texFroxel_A = pipeline.texture3D("texFroxel_A", TextureFormat.RGBA16_SFLOAT)
            .size(BufferWidth, BufferHeight, BufferDepth)
            .create();

        var texFroxel_B = pipeline.texture3D("texFroxel_B", TextureFormat.RGBA16_SFLOAT)
            .size(BufferWidth, BufferHeight, BufferDepth)
            .create();

        flipper = new Flipper<Texture3D>(texFroxel_A, texFroxel_B);

        reader = pipeline.reference3D("texFroxel_read", TextureFormat.RGBA16_SFLOAT)
            .size(BufferWidth, BufferHeight, BufferDepth)
            .createEmpty();

        writer = pipeline.reference3D("texFroxel_write", TextureFormat.RGBA16_SFLOAT)
            .size(BufferWidth, BufferHeight, BufferDepth)
            .createEmpty();
        
        reader.set(flipper.getReader());
        writer.set(flipper.getWriter());

        pipeline.sampler("froxelSampler")
            .addressMode(AddressMode.CLAMP)
            .minFilter(FilterMode.LINEAR)
            .magFilter(FilterMode.LINEAR)
            .create();
    }

    public void render(StageList stage) {
        int sizeX = (int)Math.ceil(BufferWidth / 8f);
        int sizeY = (int)Math.ceil(BufferHeight / 8f);
        int sizeZ = (int)Math.ceil(BufferDepth / 4f);

        stage.compute("froxels", "program/deferred/froxels", "main")
            .exportInt("Froxel_Width", this.BufferWidth)
            .exportInt("Froxel_Height", this.BufferHeight)
            .exportInt("Froxel_Depth", this.BufferDepth)
            .dispatch3D(sizeX, sizeY, sizeZ);
    }

    public void update() {
        flipper.flip();
        
        reader.set(flipper.getReader());
        writer.set(flipper.getWriter());
    }
}
