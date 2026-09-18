public module ray_cone;


public struct RayCone {
    public float width;
    public float spreadAngle;


    // 1. INITIALIZE FROM HYBRID RASTER GI-BUFFER
    // Call this in your raster pixel shader to save the initial cone state into your G-Buffer texture.
    // Alternatively, compute this right before launching the reflection ray if you pass screen UVs.
    public static RayCone CreateFromRaster(float2 uvCoords, float2 textureAtlasDimensions) {
        RayCone cone;
        
        // Calculate standard hardware derivatives of the current fragment's UVs
        float2 dX = ddx(uvCoords) * textureAtlasDimensions;
        float2 dY = ddy(uvCoords) * textureAtlasDimensions;
        
        // The initial pixel footprint width is the maximum screen-space variance
        cone.width = sqrt(max(dot(dX, dX), dot(dY, dY)));
        
        // Since we don't track true curvature for a minimal distance-based approach,
        // we approximate the secondary spread angle using a constant or deriving it 
        // from the camera's baseline spread angle.
        cone.spreadAngle = 0.0015f; // Reasonable default for secondary trace dispersion
        
        return cone;
    }

    // 2. RE-INITIALIZE IN THE RAY TRACING SHADER
    // If you unpack the footprint width from a G-Buffer texture (e.g., a R16_UNORM / R16F channel)
    public static RayCone CreateFromGBuffer(float unpackedWidth, float spreadAngle = 0.0015f) {
        RayCone cone;
        cone.width = unpackedWidth;
        cone.spreadAngle = spreadAngle;
        return cone;
    }

    // 3. PROPAGATE THE SECONDARY CONE
    // Projects the cone forward based on secondary ray intersection distance
    public RayCone Propagate(float hitDistance) {
        RayCone propagated;
        // Expands linearly from the starting rasterized footprint size
        propagated.width = this.width + (hitDistance * this.spreadAngle);
        propagated.width = max(propagated.width, 1e-5f); 
        propagated.spreadAngle = this.spreadAngle;
        return propagated;
    }

    public float CalculateMipLevel(float maxLevels) {
        return clamp(log2(this.width), 0.0, maxLevels);
    }

    // public float3 debug(float mip) {
    //     if (mip < 1.0) return float3(1,0,0);
    //     if (mip < 2.0) return float3(0,1,0);
    //     return float3(0,0,1);
    // }
}
