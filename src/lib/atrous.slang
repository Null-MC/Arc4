public module atrous;


#define W(x) (x/256.0)

static const float atrousKernel[25] = float[](
    W( 1), W( 4), W( 6), W( 4), W( 1),
    W( 4), W(16), W(24), W(16), W( 4),
    W( 6), W(24), W(36), W(24), W( 6),
    W( 4), W(16), W(24), W(16), W( 4),
    W( 1), W( 4), W( 6), W( 4), W( 1));

static const int2 atrousOffsets[25] = int2[](
    int2(-2, -2), int2(-1, -2), int2(0, -2), int2(1, -2), int2(2, -2),
    int2(-2, -1), int2(-1, -1), int2(0, -1), int2(1, -1), int2(2, -1),
    int2(-2,  0), int2(-1,  0), int2(0,  0), int2(1,  0), int2(2,  0),
    int2(-2,  1), int2(-1,  1), int2(0,  1), int2(1,  1), int2(2,  1),
    int2(-2,  2), int2(-1,  2), int2(0,  2), int2(1,  2), int2(2,  2));
