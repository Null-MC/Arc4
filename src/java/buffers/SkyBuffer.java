package buffers;

import org.joml.Vector3f;

public record SkyBuffer(
    // Constant base properties at sea level (Earth)
    Vector3f BETA_RAYLEIGH_BASE,
    float BETA_MIE_BASE_SCA,
    float BETA_MIE_BASE_ABS,

    // Default distribution scale heights (in meters)
    float H_R_DEFAULT,
    float H_M_DEFAULT)
{
    public static SkyBuffer Earth = new SkyBuffer(
            new Vector3f(5.80e-3f, 13.55e-3f, 33.10e-3f),
            2.00e-3f,
            4.40e-4f,
            8.0f,
            1.2f);
}
