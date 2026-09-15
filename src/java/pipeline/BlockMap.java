package pipeline;

import dev.irisshaders.aperture.api.objects.IBlockState;

public class BlockMap {
    public int getId(IBlockState block) {
        if (block.matches("water")) return 1;

        return 0;
    }
}
