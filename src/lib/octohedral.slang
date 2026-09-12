public module octohedral;

import lib.common;


namespace octohedral {

    internal half2 wrap(const in half2 v) {
        return (1.0h - abs(v.yx)) * select(v.xy >= 0.0h, 1.0h, -1.0h);
    }

    public half2 encode(half3 n) {
        n /= sumOf(abs(n));
        n.xy = n.z >= 0.0h ? n.xy : wrap(n.xy);
        n.xy = n.xy * 0.5h + 0.5h;
        return n.xy;
    }

    public half3 decode(half2 f) {
        f = f * 2.0h - 1.0h;
    
        // https://twitter.com/Stubbesaurus/status/937994790553227264
        half3 n = half3(f.xy, 1.0h - sumOf(abs(f.xy)));
        half t = saturate(-n.z);
        n.xy += select(n.xy >= 0.0h, -t, t);
        return normalize(n);
    }

}
