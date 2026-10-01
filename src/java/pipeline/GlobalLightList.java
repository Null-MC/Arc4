package pipeline;

import dev.irisshaders.aperture.api.commands.StageList;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import lib.Shader.ShaderBuilder;

public class GlobalLightList {
    public static final int SectionSizeX = 9;
    public static final int SectionSizeY = 7;
    public static final int SectionSizeZ = 9;

    public static final int GlobalMaxLightCount = 16384;
    public static final int LocalMaxLightCount = 65536;

    public static final int MaxIndexCount = SectionSizeX * SectionSizeY * SectionSizeZ;

    

    public GlobalLightList(PipelineConfig pipeline, ShaderBuilder builder) {
        pipeline.buffer("LightListCounters", 8);
        pipeline.buffer("GlobalLightIndex", GlobalMaxLightCount * 16);
        pipeline.buffer("GlobalLightMap", MaxIndexCount * 8);

        pipeline.buffer("LocalLightIndex", LocalMaxLightCount * 16);
        pipeline.buffer("LocalLightMap", MaxIndexCount * 8);

        builder.exportInt("LightList_GlobalMaxLightCount", GlobalMaxLightCount);
        builder.exportInt("LightList_LocalMaxLightCount", LocalMaxLightCount);
        builder.exportInt("LightList_MaxIndexCount", MaxIndexCount);

        builder.exportInt("LightList_SectionSizeX", SectionSizeX);
        builder.exportInt("LightList_SectionSizeY", SectionSizeY);
        builder.exportInt("LightList_SectionSizeZ", SectionSizeZ);
    }

    public void render(StageList stage, ShaderBuilder builder) {
        builder.compute(stage, "Global-Lights-Clear", "program/pre/light-list-global", shader -> {
            shader.dispatch1D(1);
        }, "clear");

        builder.compute(stage, "Global-Lights-Populate", "program/pre/light-list-global", shader -> {
            shader.dispatch3D(GlobalLightList.SectionSizeX, GlobalLightList.SectionSizeY, GlobalLightList.SectionSizeZ);
        });

        builder.compute(stage, "Local-Lights-Populate", "program/pre/light-list-local", shader -> {
            shader.dispatch3D(GlobalLightList.SectionSizeX, GlobalLightList.SectionSizeY, GlobalLightList.SectionSizeZ);
        });
    }
}
