package buffers;

public record PlanetBuffer(
    float RadiusGround_KM,
    float RadiusAtmosphere_KM)
{
    public static final PlanetBuffer Earth = new PlanetBuffer(3_360.f, 3_460.f);
}
