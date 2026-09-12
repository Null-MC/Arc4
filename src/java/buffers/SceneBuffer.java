package buffers;

import org.joml.Vector2f;

import dev.irisshaders.aperture.api.objects.Screen;
import dev.irisshaders.aperture.api.pipeline.FrameState;

public record SceneBuffer(
    Vector2f TAA_jitter)
{
    public static SceneBuffer Build(FrameState state, Screen screen) {
        Vector2f taaJitter = new Vector2f();
        if (state.settings().getBoolValue("TAA_Enabled")) {
            final var frameCounter = state.uniforms().getInt("ap.timing.frameCounter");

            taaJitter = R2(frameCounter)
                .sub(new Vector2f(0.5f))
				.div(new Vector2f(screen.renderWidth(), screen.renderHeight()));
        }

        return new SceneBuffer(taaJitter);
    }

    private static Vector2f R2(int i) {
        final double G = 1.32471795724474602596;
        final double inv_X = 1.0 / G;
        final double inv_Y = 1.0 / (G*G);

		return new Vector2f(
			(float)fract(inv_X * i + 0.5),
			(float)fract(inv_Y * i + 0.5)
		);
	}

    private static double fract(double f) {
        return f - Math.floor(f);
    }
}
