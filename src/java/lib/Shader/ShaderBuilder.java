package lib.Shader;

import java.util.function.Consumer;
import java.util.Map;
import java.util.HashMap;

import dev.irisshaders.aperture.api.commands.ComputeCommand;
import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.objects.IBlockState;
import dev.irisshaders.aperture.api.objects.ObjectShaderBuilder;
import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import dev.irisshaders.aperture.api.pipeline.ProgramUsage;

import lib.BlockMap;
import lib.BlockMapBuilder;
import lib.LightData;
import lib.LightDataManager;

public class ShaderBuilder {
    private final Screen screen;
    private final BlockMap blocks;
    private final PipelineConfig pipeline;
    private final LightDataManager lightData;

    private final Map<String, Integer> exportedInts = new HashMap<>();


    public ShaderBuilder(Screen screen, PipelineConfig pipeline) {
        this.screen = screen;
        this.pipeline = pipeline;

        blocks = new BlockMap();
        lightData = new LightDataManager(pipeline);
    }

    public void mapBlock(String export, Consumer<BlockMapBuilder> config) {
        var builder = new BlockMapBuilder();
        config.accept(builder);
        var blockData = builder.build(export);

        var blockId = blocks.map(blockData);
        exportedInts.put(export, blockId);
    }

    public ComputeCommand compute(StageList stage, String name, String file, Consumer<ComputeShaderBuilder> config, String entryPoint) {
        var shader = stage.compute(name, file, entryPoint);
        var builder = new ComputeShaderBuilder(screen, shader);

        // injectGlobals(shader);
        for (Map.Entry<String, Integer> entry : exportedInts.entrySet()) {
            shader.exportInt(entry.getKey(), entry.getValue());
        }

        config.accept(builder);
        return shader;
    }

    public ComputeCommand compute(StageList stage, String name, String file, Consumer<ComputeShaderBuilder> config) {
        return compute(stage, name, file, config, "main");
    }

    public ObjectShaderBuilder object(ProgramUsage usage, String file, Consumer<ObjectShaderBuilder> config, String entryPoint) {
        var shader = pipeline.object(usage, file, entryPoint);

        // injectGlobals(shader);
        for (Map.Entry<String, Integer> entry : exportedInts.entrySet()) {
            shader.exportInt(entry.getKey(), entry.getValue());
        }

        config.accept(shader);
        return shader;
    }

    public ObjectShaderBuilder object(ProgramUsage usage, String file, Consumer<ObjectShaderBuilder> config) {
        return object(usage, file, config, "ObjectShader");
    }

    public ObjectShaderBuilder discard(ProgramUsage usage) {
        return object(usage, "program/object/discard", shader -> {});
    }

    public ShaderBuilder exportInt(String name, int value) {
        exportedInts.put(name, value);
        return this;
    }

    public int getBlockId(IBlockState block) {
        return blocks.getId(block);
    }

    public void updateLights() {
        for (var blockId : blocks.keys()) {
            var blockData = blocks.get(blockId);
            var light = LightData.fromHexColor(blockData.light_color(), blockData.light_range());
            
            lightData.map(blockId, light);
        }

        lightData.update();
    }
    
    // TODO: this pattern won't work without a shared shader interface
    // private void injectGlobals(ComputeCommand shader) {
    //     // export block IDs
    //     // for (int blockId : Blocks.keys()) {
    //     //     shader.exportInt(Blocks.get(blockId).export(), blockId);
    //     // }

    //     // export misc integers
    //     for (Map.Entry<String, Integer> entry : exportedInts.entrySet()) {
    //         shader.exportInt(entry.getKey(), entry.getValue());
    //     }
    // }
}
