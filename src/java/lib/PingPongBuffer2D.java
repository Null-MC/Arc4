package lib;

import dev.irisshaders.aperture.api.objects.Texture2D;
import dev.irisshaders.aperture.api.objects.TextureReference2D;

/// A utility class for managing a ping-pong buffer with two 2D textures.
/// It allows flipping between the two textures across separate frames.
/// Will not work within the same frame.
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

        updateReferences();
    }

    public void reset() {
        flipper.reset();

        updateReferences();
    }

    private void updateReferences() {
        reader.set(flipper.getReader());
        writer.set(flipper.getWriter());
    }
}
