package lib;

public class BufferFlipper<T> {
    private T texA;
    private T texB;
    private boolean flipped;


    public BufferFlipper(T texA, T texB) {
        this.texA = texA;
        this.texB = texB;
    }

    public void flip() {
        flipped = !flipped;
    }

    public void reset() {
        flipped = false;
    }

    public T getReadTex() {
        return flipped ? texA : texB;
    }

    public T getWriteTex() {
        return flipped ? texB : texA;
    }
}
