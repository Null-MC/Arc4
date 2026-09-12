package buffers;

public record PlanetBuffer(
    float RadiusGround_KM,
    float RadiusAtmosphere_KM)
{
    public static PlanetBuffer Build() {
        return new PlanetBuffer(3_360.f, 3_460.f);
    }
}
