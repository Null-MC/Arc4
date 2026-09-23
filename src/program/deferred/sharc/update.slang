import aperture;
import settings;
import rt_pipeline;
import lib.common;
import lib.octohedral;
import lib.hemisphere;
import lib.sharc;
import lib.shadow;
import lib.pbr.material;
import lib.noise.blue;
import lib.sky.shared;
import lib.sky.transmit;
import lib.sky.view;


Texture2D<half4> texDeferNormal;
Texture2D<half4> texDeferSpecular;

Texture2D<half4> blockAtlasS;

static const uint SHARC_PATH_DEPTH = 3u;
extern static const int SHARC_UPDATE_TILE_SIZE;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    // Each dispatched thread owns one SHARC_UPDATE_TILE_SIZE^2 tile and samples
    // a different pixel within it each frame, so no threads are wasted.
    uint2 tileOffset = uint2(
        ap.timing.frameCounter % SHARC_UPDATE_TILE_SIZE,
        (ap.timing.frameCounter / SHARC_UPDATE_TILE_SIZE) % SHARC_UPDATE_TILE_SIZE
    );
    uint2 pixelPos = globalPos * uint(SHARC_UPDATE_TILE_SIZE) + tileOffset;
    if (any(pixelPos >= ap.game.renderSize)) return;

    float depth = ap.depth[pixelPos];
    if (depth <= 0.0) return;

    float2 texcoord = (pixelPos + 0.5) / ap.game.renderSize;
    if (userSettings.TAA_Enabled) texcoord -= scene.TAA_jitter;

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);

    // Slightly scale down the view position to avoid precision issues.
    // viewPos *= 0.99;

    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    half4 normalData = texDeferNormal[pixelPos];
    float3 geo_normal = octohedral::decode(normalData.xy);
    float3 tex_normal = octohedral::decode(normalData.zw);

    float3 sunDir = normalize(ap.celestial.sunPosition);

    half4 specularMap = texDeferSpecular[globalPos];
    float sss = getSpecularReader().sss(specularMap);

    float sssDither = BlueNoise::sampleAnimated1D(globalPos, 1, ap.timing.frameCounter);
    bool is_sss = sss > sssDither;

    float3 pathPositions[4];
    float3 pathNormals[4];
    float3 pathShadingNormals[4];
    float3 pathAlbedos[4];
    float  pathEmissions[4];
    bool  pathSss[4];
    uint pathLength = 1u;
    bool terminatedInSky = false;
    float3 skyRadiance = 0.0;

    pathPositions[0] = localPos;
    pathNormals[0] = geo_normal;
    pathShadingNormals[0] = tex_normal;
    pathAlbedos[0] = 1.0;
    pathEmissions[0] = 0.0;
    pathSss[0] = is_sss;

    for (uint bounce = 0u; bounce < SHARC_PATH_DEPTH; bounce++) {
        float2 noise = BlueNoise::sampleAnimated2D(pixelPos, 2u + bounce, ap.timing.frameCounter);
        float3 rayDir = transform_to_world(pathShadingNormals[bounce], sampleCosineWeightedHemisphere(noise));

        if (dot(rayDir, pathNormals[bounce]) < 0.0) rayDir = -rayDir;
        
        if (bounce == 0 && is_sss) rayDir = -rayDir;

        var query = HWRT.startQuery(
            pathPositions[bounce] + 0.002 * pathNormals[bounce],
            rayDir,
            0.0,
            max(ap.world.renderDistance, 1.0),
            HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
            HWRT.RTFlags.USE_TWO_STATE_OMM);

        float3 transmitColor = 1.0;
        while (query.proceed()) {
            let hit = query.getCandidate();
            let hitType = hit.getGeometryIndex();
            if (hitType == HWRT.RTGeometryIndex.SOLID) {
                query.acceptCandidate();
                continue;
            }

            let surface = HWRT.decodeHit(hit);
            float4 hit_color = surface.albedo().sampleLevel(surface.getUV(), 0.0) * surface.getColor();

            if (hitType == HWRT.RTGeometryIndex.CUTOUT) {
                if (hit_color.a >= 0.1) query.acceptCandidate();
                continue;
            }

            float3 tint = getColorSpace().fromGamma(hit_color.rgb);
            tint *= 1.0 - hit_color.a;
            // tint = lerp(1.0, tint, hit_color.a);
            transmitColor *= tint;
        }

        if (!query.hasHit()) {
            float3 skyPos = planet.getSkyPosition(pathPositions[bounce]);
            
            skyRadiance = planet.sampleView(skyPos, rayDir, sunDir);
            skyRadiance = transmitColor * getColorSpace().fromLinear(skyRadiance);
            terminatedInSky = true;
            break;
        }

        var hit = query.getHit();
        var surface = HWRT.decodeHit(hit);
        float2 hit_uv = surface.getUV();
        float3 hit_albedo = surface.albedo().sampleLevel(hit_uv, 0.0).rgb * surface.getColor().rgb;
        half4 hit_specular = blockAtlasS.SampleLevel(apt_nearestSampler, hit_uv, 0.0);

        let hit_sss = getSpecularReader().sss(hit_specular);
        bool hit_is_sss = hit_sss > sssDither;

        pathPositions[pathLength] = surface.getPos();
        pathNormals[pathLength] = surface.getNormal();
        pathShadingNormals[pathLength] = surface.getNormal();

        pathAlbedos[pathLength] = transmitColor * getColorSpace().fromGamma(hit_albedo);
        pathEmissions[pathLength] = mat_emission(hit_specular);
        pathSss[pathLength] = hit_is_sss;

        pathLength++;
    }

    float3 downstreamRadiance = 0.0;
    for (int index = int(pathLength) - 1; index >= 0; index--) {
        float3 vertexRadiance = directLighting(
            globalPos,
            pathPositions[index],
            pathNormals[index],
            pathShadingNormals[index],
            pathSss[index]);

        vertexRadiance += pathEmissions[index];

        if (index == int(pathLength) - 1 && terminatedInSky) {
            vertexRadiance += skyRadiance;
        }
        else if (index < int(pathLength) - 1) {
            // Child's own Lambertian BRDF normalization, matching hit_albedo/PI at the consumer.
            vertexRadiance += pathAlbedos[index + 1] * downstreamRadiance / PI;
        }

        sharcAccumulate(
            pathPositions[index] + ap.camera.position,
            pathNormals[index],
            vertexRadiance,
            1.0);
        
        downstreamRadiance = vertexRadiance;
    }
}


float3 directLighting(
        const in int2 globalPos,
        const in float3 localPos,
        const in float3 geo_normal,
        const in float3 tex_normal,
        const in bool sss) {
    float3 sunDir = normalize(ap.celestial.sunPosition);
    float3 moonDir = normalize(ap.celestial.moonPosition);
    float3 skyLightDir = normalize(ap.celestial.position);

    float3 skyPos = planet.getSkyPosition(localPos);
    float3 sunLight = planet.sampleTransmit(skyPos, sunDir) * SunColor;
    float3 moonLight = planet.sampleTransmit(skyPos, moonDir) * MoonColor;

    if (!sss) {
        sunLight *= max(dot(tex_normal, sunDir), 0.0);
        moonLight *= max(dot(tex_normal, moonDir), 0.0);
    }

    float3 directLight = (sunLight + moonLight);// / PI;
    return directLight * SampleShadowDisc(globalPos, localPos, geo_normal);
}
