package pipeline;

import java.util.Map;
import java.util.Set;

import dev.irisshaders.aperture.api.objects.IBlockState;

public class BlockMap {
    private final Map<Integer, BlockData> _map = new java.util.HashMap<>();
    private int mapIndex = 0;


    public int map(BlockData data) {
        var index = ++mapIndex;
        _map.put(index, data);
        return index;
    }

    public BlockData get(int id) {
        return _map.get(id);
    }

    public int map(String export, String name) {
        return map(new BlockData(export, name, "#000000", 0));
    }

    public int map(String export, String name, String light_color, int light_range) {
        return map(new BlockData(export, name, light_color, light_range));
    }

    public int getId(IBlockState block) {
        for (var block_id : _map.keySet()) {
            var block_name = _map.get(block_id).name;
            if (block.matches(block_name)) return block_id;
        }

        return 0;
    }

    public Set<Integer> keys() {
        return _map.keySet();
    }

    // public void Parse(PipelineConfig pipeline) {
    //     pipeline.
    // }

    public record BlockData(String export, String name, String light_color, int light_range) {}
}
