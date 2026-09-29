package buffers;

import dev.irisshaders.aperture.api.objects.ArraySize;

public record LightDataList(@ArraySize(256) int[] list) {}
