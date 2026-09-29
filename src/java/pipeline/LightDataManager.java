package pipeline;

import java.util.Map;

import buffers.LightDataList;
import buffers.LightData;

import dev.irisshaders.aperture.api.objects.MappedBuffer;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;


public class LightDataManager {
    private final Map<Integer, LightData> bufferMap;
    private final MappedBuffer<LightDataList> buffer;


    public LightDataManager(PipelineConfig pipeline) {
        bufferMap = new java.util.HashMap<>();

        buffer = pipeline.mappedBuffer("LightDataBuffer", LightDataList.class);
    }

    public void map(int customId, LightData data) {
        bufferMap.put(customId, data);
    }

    public void update() {
        LightData[] list = new LightData[256];
        bufferMap.forEach((customId, lightData) -> list[customId] = lightData);
        buffer.write(new LightDataList(list));
    }
}
