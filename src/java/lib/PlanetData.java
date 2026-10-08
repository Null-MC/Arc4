package lib;

import buffers.PlanetBuffer;

public class PlanetData {
    public float RadiusGround_KM;
    public float RadiusAtmosphere_KM;
    public float SunAngularRadius;
    public float MoonAngularRadius;
    

    public PlanetBuffer ToBuffer() {
        return new PlanetBuffer(
            RadiusGround_KM,
            RadiusGround_KM + RadiusAtmosphere_KM,
            SunAngularRadius,
            MoonAngularRadius);
    }
}
