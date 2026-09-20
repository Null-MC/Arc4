package lib;

/// A utility class for managing a pair of objects that can be flipped between a reader and a writer.
/// The reader and writer roles are swapped each time the flip() method is called.
/// Use this to alternate between two objects within the same frame.
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
