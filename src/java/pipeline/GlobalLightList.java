package pipeline;

import dev.irisshaders.aperture.api.pipeline.PipelineConfig;
import lib.Shader.ShaderBuilder;

public class GlobalLightList {
    public static final int GlobalLight_SectionSizeX = 9;
    public static final int GlobalLight_SectionSizeY = 8;
    public static final int GlobalLight_SectionSizeZ = 9;

    public static final int GlobalMaxLightCount = 4096;
    public static final int GlobalMaxIndexCount = GlobalLight_SectionSizeX * GlobalLight_SectionSizeY * GlobalLight_SectionSizeZ;


    public GlobalLightList(PipelineConfig pipeline, ShaderBuilder builder) {
        pipeline.buffer("GlobalLightCounter", 4);
        pipeline.buffer("GlobalLightIndex", GlobalMaxLightCount * 16);
        pipeline.buffer("GlobalLightMap", GlobalMaxIndexCount * 8);

        builder.exportInt("GlobalMaxLightCount", GlobalMaxLightCount);
        builder.exportInt("GlobalMaxIndexCount", GlobalMaxIndexCount);

        builder.exportInt("GlobalLight_SectionSizeX", GlobalLight_SectionSizeX);
        builder.exportInt("GlobalLight_SectionSizeY", GlobalLight_SectionSizeY);
        builder.exportInt("GlobalLight_SectionSizeZ", GlobalLight_SectionSizeZ);
    }
}
