package lib;

import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureReference2D;

public class PingPongBuffer2D {
    private final Flipper<Texture2D> flipper;
    private final TextureReference2D reader;
    private final TextureReference2D writer;


    public PingPongBuffer2D(Texture2D texture_A, Texture2D texture_B, TextureReference2D reader, TextureReference2D writer) {
        this.reader = reader;
        this.writer = writer;

        flipper = new Flipper<Texture2D>(texture_A, texture_B);

        reader.set(flipper.getReader());
        writer.set(flipper.getWriter());
    }

    public void flip() {
        flipper.flip();

        reader.set(flipper.getReader());
        writer.set(flipper.getWriter());
    }

    public void reset() {
        flipper.reset();
    }
}
