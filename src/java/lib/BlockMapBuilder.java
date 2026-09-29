package lib;

import lib.BlockMap.BlockData;

public class BlockMapBuilder {
    private String[] matches;
    private String light_color = "#000000";
    private int light_range = 0;


    public BlockMapBuilder matches(String[] matches) {
        this.matches = matches;
        return this;
    }
    
    public BlockMapBuilder matches(String match) {
        this.matches = new String[]{match};
        return this;
    }

    public BlockMapBuilder setLightColor(String light_color) {
        this.light_color = light_color;
        return this;
    }

    public BlockMapBuilder setLightRange(int light_range) {
        this.light_range = light_range;
        return this;
    }

    public BlockData build(String export) {
        // TODO: validate and throw exception

        return new BlockData(export, matches, light_color, light_range);
    }
}
