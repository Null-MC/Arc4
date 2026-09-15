import java.util.function.Consumer;

import dev.irisshaders.aperture.api.PackSettings;
import dev.irisshaders.aperture.api.settings.OptionType;
import dev.irisshaders.aperture.api.settings.SettingsManager;
import dev.irisshaders.aperture.api.settings.SettingsScreen;


public class settings implements PackSettings {
	@Override
	public void createSettings(SettingsManager manager, SettingsScreen screen) {
        screen.option("SunAngle", OptionType.floatType(-90.0f, 90.0f, 2.0f, 2.0f), true);
        screen.option("SeaLevel", OptionType.floatType(0.0f, 256.0f, 5.0f, 60.0f), true);
        screen.option("TAA_Enabled", OptionType.boolType(true), false);
        screen.option("Accumulation", OptionType.boolType(false), false);

        subscreen(screen, "Shadows", screen_shadows -> {
            screen_shadows.option("Shadow_Resolution", OptionType.intType(new int[] {512, 1024, 2048, 4096}, 1024), false);
        });

        subscreen(screen, "Sky", screen_sky -> {
            screen_sky.option("Sky_BarometricPressure", OptionType.floatType(0.85f, 1.15f, 0.01f, 1.0f), true);
            screen_sky.option("Sky_Turbidity", OptionType.floatType(1.0f, 200.0f, 0.5f, 2.0f), true);
            screen_sky.option("Sky_Humidity", OptionType.floatType(0.0f, 1.0f, 0.05f, 0.4f), true);
            screen_sky.option("Sky_FogIntensity", OptionType.floatType(0.0f, 1.0f, 0.05f, 0.0f), true);
            screen_sky.option("Sky_PollutionColor_R", OptionType.floatType(0.0f, 1.0f, 0.05f, 0.0f), true);
            screen_sky.option("Sky_PollutionColor_G", OptionType.floatType(0.0f, 1.0f, 0.05f, 0.0f), true);
            screen_sky.option("Sky_PollutionColor_B", OptionType.floatType(0.0f, 1.0f, 0.05f, 0.0f), true);
        });

        subscreen(screen, "Bloom", screen_bloom -> {
            screen_bloom.option("Bloom_Enabled", OptionType.boolType(true), false);
            screen_bloom.option("Bloom_Strength", OptionType.floatType(0.0f, 8.0f, 0.2f, 2.0f), true);
        });

        subscreen(screen, "Exposure", screen_exposure -> {
            screen_exposure.option("Exposure_Min", OptionType.floatType(-6.0f, 0.0f, 0.2f, -3.0f), true);
            screen_exposure.option("Exposure_Max", OptionType.floatType(0.0f, 20.0f, 0.2f, 16.0f), true);
            screen_exposure.option("Exposure_Offset", OptionType.floatType(-2.0f, 6.0f, 0.2f, 3.4f), true);
        });

        subscreen(screen, "Debug", screen_debug -> {
            screen_debug.option("Debug_WhiteWorld", OptionType.boolType(false), false);
            screen_debug.option("Debug_SkyLuts", OptionType.boolType(false), false);
            screen_debug.option("Debug_Exposure", OptionType.boolType(false), false);
        });
    }

    private void subscreen(SettingsScreen parent, String name, Consumer<SettingsScreen> callback) {
        callback.accept(parent.child(name));
    }
}
