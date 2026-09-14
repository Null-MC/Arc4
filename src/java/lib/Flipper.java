package lib;

public class Flipper<T> implements IFlipper {
    private T objA;
    private T objB;
    private boolean flipped;


    public Flipper(T objA, T objB) {
        this.objA = objA;
        this.objB = objB;
    }

    public void flip() {
        flipped = !flipped;
    }

    public void reset() {
        flipped = false;
    }

    public T getReader() {
        return flipped ? objA : objB;
    }

    public T getWriter() {
        return flipped ? objB : objA;
    }
}
