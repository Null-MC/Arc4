package lib;

import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureReference;

public class PingPongBuffer {
    private final BufferFlipper<Texture2D> flipper;
    private final TextureReference reader;
    private final TextureReference writer;


    public PingPongBuffer(Texture2D texture_A, Texture2D texture_B, TextureReference reader, TextureReference writer) {
        this.reader = reader;
        this.writer = writer;

        flipper = new BufferFlipper<Texture2D>(texture_A, texture_B);
    }

    public void flip() {
        flipper.flip();

        reader.set(flipper.getReadTex());
        writer.set(flipper.getWriteTex());
    }

    public void reset() {
        flipper.reset();
    }
}
