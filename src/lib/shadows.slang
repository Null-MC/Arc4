public module shadows;

import aperture;
import lib.common;


Optional<ShadowCascade> getShadowCascade(const in float3 shadowViewPos) {
	for (int i = 0; i < ap.celestial.cascadeCount; i++) {
        float3 shadowPos = mul3(ap.celestial.projection[i], shadowViewPos);
		shadowPos.xy = shadowPos.xy * 0.5 + 0.5;

        if (all(saturate(shadowPos) == shadowPos))
            return ShadowCascade(shadowPos, i);
	}

	return none;
}

struct ShadowCascade {
	float3 position;
	int cascade;
}
