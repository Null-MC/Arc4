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

Texture2D<half4> blockAtlasS;

static const uint SHARC_PATH_DEPTH = 3u;


[[shader("compute")]]
[numthreads(16,16)]
void main(uint2 globalPos : SV_DispatchThreadID) {
    if (any(globalPos >= ap.game.renderSize)) return;

    // Process a sparse, temporally distributed subset of primary pixels.
    uint sampleIndex = globalPos.x + globalPos.y * ap.game.renderSize.x;
    if ((sampleIndex + ap.timing.frameCounter * 17u) % 5u != 0u) return;

    float depth = ap.depth[globalPos];
    if (depth <= 0.0) return;

    float2 texcoord = (globalPos + 0.5) / ap.game.renderSize;
    if (userSettings.TAA_Enabled) texcoord -= scene.TAA_jitter;

    float3 clipPos = float3(texcoord * 2.0 - 1.0, depth);
    float3 viewPos = mul_project(ap.camera.projectionInv, clipPos);
    float3 localPos = mul3(ap.camera.viewInv, viewPos);

    half4 normalData = texDeferNormal[globalPos];
    float3 geo_normal = octohedral::decode(normalData.xy);
    float3 tex_normal = octohedral::decode(normalData.zw);

    float3 sunDir = normalize(ap.celestial.sunPosition);

    float3 pathPositions[4];
    float3 pathNormals[4];
    float3 pathShadingNormals[4];
    float3 pathAlbedos[4];
    float  pathEmissions[4];
    uint pathLength = 1u;
    bool terminatedInSky = false;
    float3 skyRadiance = 0.0;

    pathPositions[0] = localPos;
    pathNormals[0] = geo_normal;
    pathShadingNormals[0] = tex_normal;
    pathAlbedos[0] = 1.0;
    pathEmissions[0] = 0.0;

    for (uint bounce = 0u; bounce < SHARC_PATH_DEPTH; bounce++) {
        float2 noise = BlueNoise::sampleAnimated2D(globalPos, 2u + bounce, ap.timing.frameCounter);
        float3 rayDir = transform_to_world(pathShadingNormals[bounce], sampleCosineWeightedHemisphere(noise));

        var query = HWRT.startQuery(
            pathPositions[bounce] + 0.04 * pathNormals[bounce],
            rayDir,
            0.0,
            max(ap.world.renderDistance, 1.0),
            HWRT.HitType.TERRAIN | HWRT.HitType.ENTITY,
            HWRT.RTFlags.NONE);

        float3 transmitColor = 1.0;
        while (query.proceed()) {
            let candidate = query.getCandidate();
            let candidateSurface = HWRT.decodeHit(candidate);
            float4 candidateColor = candidateSurface.albedo().sampleLevel(candidateSurface.getUV(), 0.0) * candidateSurface.getColor();

            if (candidateColor.a >= 0.99) query.acceptCandidate();
            else {
                float3 tint = transformer.fromGamma(candidateColor.rgb);
                transmitColor *= tint * (1.0 - pow2(candidateColor.a));
            }
        }

        if (!query.hasHit()) {
            float3 skyPos = planet.getSkyPosition(pathPositions[bounce]);
            skyRadiance = planet.sampleView(skyPos, rayDir, sunDir);
            
            skyRadiance = PI * transmitColor * transformer.fromLinear(skyRadiance);
            terminatedInSky = true;
            break;
        }

        var hit = query.getHit();
        var surface = HWRT.decodeHit(hit);
        pathPositions[pathLength] = surface.getPos();
        pathNormals[pathLength] = surface.getNormal();
        pathShadingNormals[pathLength] = surface.getNormal();

        float2 hit_uv = surface.getUV();
        float3 hit_albedo = surface.albedo().sampleLevel(hit_uv, 0.0).rgb * surface.getColor().rgb;
        half4 hit_specular = blockAtlasS.SampleLevel(apt_nearestSampler, hit_uv, 0.0);
        pathAlbedos[pathLength] = transmitColor * transformer.fromGamma(hit_albedo);
        pathEmissions[pathLength] = mat_emission(hit_specular.a);

        pathLength++;
    }

    float3 downstreamRadiance = 0.0;
    for (int index = int(pathLength) - 1; index >= 0; index--) {
        float3 vertexRadiance = directLighting(
            pathPositions[index],
            pathNormals[index],
            pathShadingNormals[index]);

        vertexRadiance += pathEmissions[index];

        if (index == int(pathLength) - 1 && terminatedInSky) {
            vertexRadiance += skyRadiance;
        }
        else if (index < int(pathLength) - 1) {
            vertexRadiance += pathAlbedos[index + 1] * downstreamRadiance;
        }

        sharcAccumulate(
            pathPositions[index] + ap.camera.position,
            pathNormals[index],
            vertexRadiance,
            1.0);
        
        downstreamRadiance = vertexRadiance;
    }
}


float3 directLighting(const in float3 localPos, const in float3 geo_normal, const in float3 tex_normal) {
    float3 sunDir = normalize(ap.celestial.sunPosition);
    float3 moonDir = normalize(ap.celestial.moonPosition);
    float3 skyLightDir = normalize(ap.celestial.position);

    float3 skyPos = planet.getSkyPosition(localPos);
    float3 result = planet.sampleTransmit(skyPos, sunDir) * SunColor * max(dot(tex_normal, sunDir), 0.0);
    result += planet.sampleTransmit(skyPos, moonDir) * MoonColor * max(dot(tex_normal, moonDir), 0.0);

    return result * SampleShadow(localPos, geo_normal);
}
