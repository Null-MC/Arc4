import lib.Shader.ShaderBuilder;

public class blocks {
    private static final String color_Fire = "#ee940c";
    private static final String color_SoulFire = "#4794c0";


    public static void map(ShaderBuilder builder) {
        builder.mapBlock("BLOCK_WATER", b -> b
            .matches("water"));

        builder.mapBlock("BLOCK_LAVA", b -> b
            .matches("lava")
            .setLightColor("#d6801e")
            .setLightRange(15));

        builder.mapBlock("BLOCK_CAMPFIRE_LIT", b -> b
            .matches("campfire")
            .setLightColor(color_Fire)
            .setLightRange(15));

        builder.mapBlock("BLOCK_COPPER_TORCH", b -> b
            .matches(new String[]{"copper_torch", "copper_wall_torch"})
            .setLightColor("#72af2c")
            .setLightRange(14));

        builder.mapBlock("BLOCK_FIRE", b -> b
            .matches("fire")
            .setLightColor(color_Fire)
            .setLightRange(15));

        builder.mapBlock("BLOCK_FROGLIGHT_OCHRE", b -> b
            .matches("ochre_froglight")
            .setLightColor("#cde951")
            .setLightRange(15));

        builder.mapBlock("BLOCK_FROGLIGHT_PEARLESCENT", b -> b
            .matches("pearlescent_froglight")
            .setLightColor("#d82b8a")
            .setLightRange(15));

        builder.mapBlock("BLOCK_FROGLIGHT_VERDANT", b -> b
            .matches("verdant_froglight")
            .setLightColor("#388a57")
            .setLightRange(15));

        builder.mapBlock("BLOCK_GLOW_LICHEN", b -> b
            .matches("glow_lichen")
            .setLightColor("#3b8164")
            .setLightRange(7));

        builder.mapBlock("BLOCK_GLOWSTONE", b -> b
            .matches("glowstone")
            .setLightColor("#cebc54")
            .setLightRange(15));

        builder.mapBlock("BLOCK_LANTERN", b -> b
            .matches("lantern")
            .setLightColor("#ee940c")
            .setLightRange(15));

        builder.mapBlock("BLOCK_MAGMA", b -> b
            .matches("magma_block")
            .setLightColor("#9e7425")
            .setLightRange(3));

        builder.mapBlock("BLOCK_REDSTONE_LAMP", b -> b
            .matches("redstone_lamp")
            .setLightColor("#eb9a64")
            .setLightRange(14));

        builder.mapBlock("BLOCK_REDSTONE_TORCH", b -> b
            .matches(new String[]{"redstone_torch", "redstone_wall_torch"})
            .setLightColor("#ee390c")
            .setLightRange(7));

        builder.mapBlock("BLOCK_SEA_LANTERN", b -> b
            .matches("sea_lantern")
            .setLightColor("#cde7eb")
            .setLightRange(15));

        builder.mapBlock("BLOCK_SOUL_CAMPFIRE", b -> b
            .matches("soul_campfire")
            .setLightColor(color_SoulFire)
            .setLightRange(10));

        builder.mapBlock("BLOCK_SOUL_FIRE", b -> b
            .matches("soul_fire")
            .setLightColor(color_SoulFire)
            .setLightRange(10));

        builder.mapBlock("BLOCK_SOUL_LANTERN", b -> b
            .matches("soul_lantern")
            .setLightColor(color_SoulFire)
            .setLightRange(10));

        builder.mapBlock("BLOCK_SOUL_TORCH", b -> b
            .matches(new String[]{"soul_torch", "soul_wall_torch"})
            .setLightColor(color_SoulFire)
            .setLightRange(10));

        builder.mapBlock("BLOCK_STAINED_GLASS", b -> b
            .matches(new String[]{
                "red_stained_glass",
                "green_stained_glass",
                "blue_stained_glass",
                "tinted_glass"
            }));

        builder.mapBlock("BLOCK_TORCH", b -> b
            .matches(new String[]{"torch", "wall_torch"})
            .setLightColor("#df9036")
            .setLightRange(14));
    }
}
