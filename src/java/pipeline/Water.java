package pipeline;

import dev.irisshaders.aperture.api.objects.AddressMode;
import dev.irisshaders.aperture.api.objects.FilterMode;
import dev.irisshaders.aperture.api.pipeline.PipelineConfig;

public class Water {
    public Water(PipelineConfig pipeline) {
        pipeline.loadPNGTexture("texWaterNoiseA", "assets/water_noise_a.png");
        pipeline.loadPNGTexture("texWaterNoiseB", "assets/water_noise_b.png");
        pipeline.loadPNGTexture("texWaterDisplacement", "assets/water_displacement.png");

        pipeline.sampler("samplerWater")
            .addressMode(AddressMode.REPEAT)
            .minFilter(FilterMode.LINEAR)
            .magFilter(FilterMode.LINEAR)
            .create();
    }
}
