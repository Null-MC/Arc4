package lib;

import java.util.Map;
import java.util.Set;

import dev.irisshaders.aperture.api.objects.IBlockState;

public class BlockMap {
    private final Map<Integer, BlockData> id_map = new java.util.HashMap<>();
    private final Map<String, Integer> name_map = new java.util.HashMap<>();
    private int mapIndex = 0;


    public int map(BlockData data) {
        var index = ++mapIndex;
        id_map.put(index, data);

        for (var name : data.names) {
            name_map.put(name, index);
        }

        return index;
    }

    public BlockData get(int id) {
        return id_map.get(id);
    }

    public int getId(IBlockState block) {
        // for (var block_id : _map.keySet()) {
        //     var block_name = _map.get(block_id).name;
        //     if (block.matches(block_name)) return block_id;
        // }

        var name = block.getBlockId().path();
        return name_map.getOrDefault(name, 0);
    }

    public Set<Integer> keys() {
        return id_map.keySet();
    }

    // public void Parse(PipelineConfig pipeline) {
    //     pipeline.
    // }

    public record BlockData(String export, String[] names, String light_color, int light_range) {}
}
