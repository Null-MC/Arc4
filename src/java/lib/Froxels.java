package lib;

import java.text.Format;

import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.objects.Texture3D;
import dev.irisshaders.aperture.api.objects.TextureFormat;
import dev.irisshaders.aperture.api.objects.TextureReference;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class Froxels {
    private final BufferFlipper<Texture3D> flipper;
    private final TextureReference reader;
    private final TextureReference writer;

    public int BufferWidth;
    public int BufferHeight;
    public int BufferDepth;

    
    public Froxels(PipelineConfig pipeline, Screen screen) {
        BufferWidth = (int)Math.ceil(screen.renderWidth() / 8f);
        BufferHeight = (int)Math.ceil(screen.renderHeight() / 8f);
        BufferDepth = 128;

        var texFroxel_A = pipeline.texture3D("texFroxel_A", TextureFormat.RGBA16_SFLOAT)
            .size(BufferWidth, BufferHeight, BufferDepth)
            .create();

        var texFroxel_B = pipeline.texture3D("texFroxel_B", TextureFormat.RGBA16_SFLOAT)
            .size(BufferWidth, BufferHeight, BufferDepth)
            .create();

        flipper = new BufferFlipper<Texture3D>(texFroxel_A, texFroxel_B);

        reader = pipeline.reference("texFroxel_read", TextureFormat.RGBA16_SFLOAT)
            // .size(BufferWidth, BufferHeight, BufferDepth)
            .createEmpty();

        writer = pipeline.reference("texFroxel_write", TextureFormat.RGBA16_SFLOAT)
            // .size(BufferWidth, BufferHeight, BufferDepth)
            .createEmpty();
    }

    public void render(StageList stage) {
        int sizeX = (int)Math.ceil(BufferWidth / 16f);
        int sizeY = (int)Math.ceil(BufferHeight / 16f);
        int sizeZ = (int)Math.ceil(BufferDepth / 16f);

        stage.compute("froxels", "composite/froxels", "updateFroxels")
            .dispatch3D(sizeX, sizeY, sizeZ)
            .exportInt("Froxel_Width", this.BufferWidth)
            .exportInt("Froxel_Height", this.BufferHeight)
            .exportInt("Froxel_Depth", this.BufferDepth);
    }

    public void update() {
        flipper.flip();
        
        // reader.set(flipper.getReadTex());
        // writer.set(flipper.getWriteTex());
    }
}
