import java.util.function.Consumer;

import dev.irisshaders.aperture.api.PackSettings;
import dev.irisshaders.aperture.api.settings.OptionType;
import dev.irisshaders.aperture.api.settings.SettingsManager;
import dev.irisshaders.aperture.api.settings.SettingsScreen;


public class settings implements PackSettings {
	@Override
	public void createSettings(SettingsManager manager, SettingsScreen screen) {
        screen.option("Accumulation", OptionType.boolType(false), false);
        screen.option("SunAngle", OptionType.floatType(-90.0f, 90.0f, 2.0f, 20.0f), true);
        screen.option("SeaLevel", OptionType.floatType(0.0f, 256.0f, 5.0f, 60.0f), true);

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
    }

    private void subscreen(SettingsScreen parent, String name, Consumer<SettingsScreen> callback) {
        callback.accept(parent.child(name));
    }
}
