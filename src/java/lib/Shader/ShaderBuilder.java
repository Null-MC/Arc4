package lib.Shader;

import java.util.function.Consumer;

import dev.irisshaders.aperture.api.commands.ComputeCommand;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.Screen;
import lib.BlockMap;
import lib.BlockMapBuilder;

public class ShaderBuilder {
    private final Screen screen;
    public final BlockMap Blocks;


    public ShaderBuilder(Screen screen) {
        this.screen = screen;

        Blocks = new BlockMap();
    }

    public void mapBlock(String export, Consumer<BlockMapBuilder> config) {
        var builder = new BlockMapBuilder();
        config.accept(builder);
        Blocks.map(builder.build(export));
    }

    public ComputeCommand compute(StageList stage, String name, String file, Consumer<ComputeShaderBuilder> config, String entryPoint) {
        var shader = stage.compute(name, file, entryPoint);
        var builder = new ComputeShaderBuilder(screen, shader);

        injectGlobals(shader);
        config.accept(builder);

        return shader;
    }

    public ComputeCommand compute(StageList stage, String name, String file, Consumer<ComputeShaderBuilder> config) {
        return compute(stage, name, file, config, "main");
    }

    private void injectGlobals(ComputeCommand shader) {
        for (int blockId : Blocks.keys()) {
            shader.exportInt(Blocks.get(blockId).export(), blockId);
        }
    }
}
