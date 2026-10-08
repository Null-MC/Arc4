public module clouds;

import aperture;
import settings;
import lib.common;
import lib.sky.shared;
import lib.sky.view;
import lib.sky.transmit;
import lib.sky.multiscatter;


static const bool CloudShadowsEnabled = true;
static const float CloudShadowStrength = 1.0;

static const int minRayMarchSteps = 35;
static const int maxRayMarchSteps = 80;
static const float cloud_height = 1500.0;
static const float maxHeight = 3200.0;
static const float cloudMieG = 0.7; // Values close to 1 will create a strong peak of luminance around the sun and weak elsewhere, values close to 0 means uniform fog. [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 ]
static const float cloudMieG2 = 0.2; // Multiple scattering approximation. Values close to 1 will create a strong peak of luminance around the sun and weak elsewhere, values close to 0 means uniform fog. [0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.1 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.2 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.3 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.4 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.5 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.6 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.7 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.8 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.9 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 ]
static const int cloud_LevelOfDetail = 2; // Number of fbm noise iterations for on-screen clouds (-1 is no fbm)	[-1 0 1 2 3 4 5 6 7 8]
static const int cloud_ShadowLevelOfDetail = 0; // Number of fbm noise iterations for the shadowing of on-screen clouds (-1 is no fbm)	[-1 0 1 2 3 4 5 6 7 8]
static const float cloudDensity = 0.0514; // Cloud Density, 0.04-0.06 is around irl values	[0.0010 0.0011 0.0013 0.0015 0.0017 0.0020 0.0023 0.0026 0.0030 0.0034 0.0039 0.0045 0.0051 0.0058 0.0067 0.0077 0.0088 0.0101 0.0115 0.0132 0.0151 0.0173 0.0199 0.0228 0.0261 0.0299 0.0342 0.0392 0.0449 0.0514 0.0589 0.0675 0.0773 0.0885 0.1014 0.1162 0.1331 0.1524 0.1746 0.2000]
static const float cloudCoverage = -0.35; // Cloud coverage	[-1.00 -0.98 -0.96 -0.94 -0.92 -0.90 -0.88 -0.86 -0.84 -0.82 -0.80 -0.78 -0.76 -0.74 -0.72 -0.70 -0.68 -0.66 -0.64 -0.62 -0.60 -0.58 -0.56 -0.54 -0.52 -0.50 -0.48 -0.46 -0.44 -0.42 -0.40 -0.38 -0.36 -0.34 -0.32 -0.30 -0.28 -0.26 -0.24 -0.22 -0.20 -0.18 -0.16 -0.14 -0.12 -0.10 -0.08 -0.06 -0.04 -0.02 0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20 0.22 0.24 0.26 0.28 0.30 0.32 0.34 0.36 0.38 0.40 0.42 0.44 0.46 0.48 0.50 0.52 0.54 0.56 0.58 0.60 0.62 0.64 0.66 0.68 0.70 0.72 0.74 0.76 0.78 0.80 0.82 0.84 0.86 0.88 0.90 0.92 0.94 0.96 0.98 1.00]
static const float fbmAmount = 0.70; // Amount of noise added to the cloud shape	[0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20 0.22 0.24 0.26 0.28 0.30 0.32 0.34 0.36 0.38 0.40 0.42 0.44 0.46 0.48 0.50 0.52 0.54 0.56 0.58 0.60 0.62 0.64 0.66 0.68 0.70 0.72 0.74 0.76 0.78 0.80 0.82 0.84 0.86 0.88 0.90 0.92 0.94 0.96 0.98 1.00 1.02 1.04 1.06 1.08 1.10 1.12 1.14 1.16 1.18 1.20 1.22 1.24 1.26 1.28 1.30 1.32 1.34 1.36 1.38 1.40 1.42 1.44 1.46 1.48 1.50 1.52 1.54 1.56 1.58 1.60 1.62 1.64 1.66 1.68 1.70 1.72 1.74 1.76 1.78 1.80 1.82 1.84 1.86 1.88 1.90 1.92 1.94 1.96 1.98 2.00 2.02 2.04 2.06 2.08 2.10 2.12 2.14 2.16 2.18 2.20 2.22 2.24 2.26 2.28 2.30 2.32 2.34 2.36 2.38 2.40 2.42 2.44 2.46 2.48 2.50 2.52 2.54 2.56 2.58 2.60 2.62 2.64 2.66 2.68 2.70 2.72 2.74 2.76 2.78 2.80 2.82 2.84 2.86 2.88 2.90 2.92 2.94 2.96 2.98 3.00]
static const float fbmPower1 = 3.00; // Higher values increases high frequency details of the cloud shape	[1.50 1.52 1.54 1.56 1.58 1.60 1.62 1.64 1.66 1.68 1.70 1.72 1.74 1.76 1.78 1.80 1.82 1.84 1.86 1.88 1.90 1.92 1.94 1.96 1.98 2.00 2.02 2.04 2.06 2.08 2.10 2.12 2.14 2.16 2.18 2.20 2.22 2.24 2.26 2.28 2.30 2.32 2.34 2.36 2.38 2.40 2.42 2.44 2.46 2.48 2.50 2.52 2.54 2.56 2.58 2.60 2.62 2.64 2.66 2.68 2.70 2.72 2.74 2.76 2.78 2.80 2.82 2.84 2.86 2.88 2.90 2.92 2.94 2.96 2.98 3.00 3.02 3.04 3.06 3.08 3.10 3.12 3.14 3.16 3.18 3.20 3.22 3.24 3.26 3.28 3.30 3.32 3.34 3.36 3.38 3.40 3.42 3.44 3.46 3.48 3.50 3.52 3.54 3.56 3.58 3.60 3.62 3.64 3.66 3.68 3.70 3.72 3.74 3.76 3.78 3.80 3.82 3.84 3.86 3.88 3.90 3.92 3.94 3.96 3.98 4.00]
static const float fbmPower2 = 2.00; // Lower values increases high frequency details of the cloud shape	[1.50 1.52 1.54 1.56 1.58 1.60 1.62 1.64 1.66 1.68 1.70 1.72 1.74 1.76 1.78 1.80 1.82 1.84 1.86 1.88 1.90 1.92 1.94 1.96 1.98 2.00 2.02 2.04 2.06 2.08 2.10 2.12 2.14 2.16 2.18 2.20 2.22 2.24 2.26 2.28 2.30 2.32 2.34 2.36 2.38 2.40 2.42 2.44 2.46 2.48 2.50 2.52 2.54 2.56 2.58 2.60 2.62 2.64 2.66 2.68 2.70 2.72 2.74 2.76 2.78 2.80 2.82 2.84 2.86 2.88 2.90 2.92 2.94 2.96 2.98 3.00 3.02 3.04 3.06 3.08 3.10 3.12 3.14 3.16 3.18 3.20 3.22 3.24 3.26 3.28 3.30 3.32 3.34 3.36 3.38 3.40 3.42 3.44 3.46 3.48 3.50 3.52 3.54 3.56 3.58 3.60 3.62 3.64 3.66 3.68 3.70 3.72 3.74 3.76 3.78 3.80 3.82 3.84 3.86 3.88 3.90 3.92 3.94 3.96 3.98 4.00]

Texture2D<float4> texCloudNoise;


float phaseg(float x, float g) {
    float gg = g * g;
    return (gg * -0.25 /PI + 0.25 /PI) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5);
}

// 3D noise from 2d texture
float densityAtPos(float3 pos) {
	pos /= 18.0;
	pos.xz *= 0.5;

	float3 p = floor(pos);
	float3 f = fract(pos);

	f = (f*f) * (3.0-2.0*f);

	float2 uv =  p.xz + f.xz + p.y * float2(0.0, 193.0);

	float2 coord =  uv / 512.0;

	// The y channel has an offset to avoid using two textures fetches
	float2 xy = texCloudNoise.Sample(sampler_linearRepeat, coord).yx;

	return lerp(xy.r, xy.g, f.y);
}

// Cloud without 3D noise, is used to exit early lighting calculations if there is no cloud
float cloudCov(float altitude_KM, float2 samplePos) {
    float noise = texCloudNoise.Sample(sampler_linearRepeat, (samplePos + sin(dot(samplePos, float2(0.5)) / 1000.0) * 600.0) / 10000.0).r;

	float mult = max(altitude_KM - 2.0, 0.0) / 2.0;
	float mult2 = max(-altitude_KM + 2.0, 0.0) / 0.5;
	float coverage = max((noise + 0.8*ap.world.rainStrength + 0.1) / (1.1 + 0.8*ap.world.rainStrength) + cloudCoverage/2.5, 0.0);
	float cloud = pow2(coverage)*4.0 - pow3(mult)*5.0 - pow2(mult2)*0.2;
	return max(cloud, 0.0);
}

// Erode cloud with 3d Perlin-worley noise, actual cloud value
// float cloudVol(float3 pos, float3 samplePos, float cov, int LoD) {
float cloudVol(float3 samplePos, float cov, int LoD) {
	float noise = 0.0;
	float totalWeights = 0.0;
	float pw = log(fbmPower1);
	float pw2 = log(fbmPower2);
	samplePos.xz += ap.timing.timeElapsed * 9.0;

	for (int i = 0; i <= LoD; i++) {
	  	float weight = exp(-i * pw2);
		noise += weight - densityAtPos(samplePos * 8.0 * exp(i*pw)) * weight;
		totalWeights += weight;
	}

	noise /= totalWeights;
	noise = noise*noise;
	return max(cov - noise*noise * (1.1 + ap.world.rainStrength) * fbmAmount, 0.0);
}

float getCloudDensity(const in float3 skyPos, const in int LoD) {
    // float3 worldPos = localPos + ap.camera.position;
    float3 worldPos = skyPos*1000.0 + float3(ap.camera.position.xz, 0.0).xzy;
	float3 samplePos = worldPos * float3(1.0, 1.0/32.0, 1.0) / 4.0 + ap.timing.timeElapsed * float3(0.5, 0.0, 0.5) * 5.0;

    float altitude_KM = planet.getSkyAltitude(skyPos);

	float coverageSP = cloudCov(altitude_KM, samplePos.xz);
	if (coverageSP <= 0.001) return 0.0;

	// if (LoD < 0) {
	// 	return max(coverageSP - 0.27 * (fbmAmount + ap.world.rainStrength), 0.0);
	// }

	return cloudVol(samplePos, coverageSP, LoD);
}

float getCloudDensity(in float3 localPos, in float3 skyPos, in int LoD) {
    // float3 worldPos = localPos + ap.camera.position;
    float3 worldPos = skyPos*1000.0 + float3(ap.camera.position.xz, 0.0).xzy;
	float3 samplePos = worldPos * float3(1.0, 1.0/32.0, 1.0) / 4.0 + ap.timing.timeElapsed * float3(0.5, 0.0, 0.5) * 5.0;

    float altitude_KM = planet.getSkyAltitude(skyPos);

	float coverageSP = cloudCov(altitude_KM, samplePos.xz);
	if (coverageSP <= 0.001) return 0.0;

	// if (LoD < 0) {
	// 	return max(coverageSP - 0.27 * (fbmAmount + ap.world.rainStrength), 0.0);
	// }

	return cloudVol(samplePos, coverageSP, LoD);
}

// float4 renderClouds(float3 viewPos, float3 color, float dither, float3 sunColor, float3 moonColor, float3 avgAmbient) {
float4 renderClouds(float3 viewDir, float3 localDir, float dither) {
    float3 sunLocalDir = normalize(ap.celestial.sunPosition);
    float3 moonLocalDir = normalize(ap.celestial.moonPosition);

    float3 sunViewDir = mul_rotate(ap.camera.view, sunLocalDir);

    float3 cameraLocalPos = 0.0;
    cameraLocalPos.y = max(userSettings.SeaLevel - ap.camera.position.y, 0.002);
    float3 cameraSkyPos = planet.getSkyPosition(cameraLocalPos);

    float planetDist = planet.rayIntersectsGround(cameraSkyPos, localDir);
    float cloudNearDist = rayIntersectSphere(cameraSkyPos, localDir, planet.RadiusGround_KM + cloud_height*0.001);
    float cloudFarDist  = rayIntersectSphere(cameraSkyPos, localDir, planet.RadiusGround_KM + maxHeight*0.001);

    float cloudDistMin = min(cloudNearDist, cloudFarDist);
    float cloudDistMax = max(cloudNearDist, cloudFarDist);

    cloudDistMin = max(cloudDistMin, ap.camera.near);

    if (planetDist >= 0.0 && planetDist < cloudDistMin) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float3 trace_localStart = localDir * (cloudDistMin * 1000.0);
    float3 trace_localEnd = localDir * (cloudDistMax * 1000.0);

    int maxIT_clouds = maxRayMarchSteps;// int(clamp(minRayMarchSteps / sqrt(localDir.y), 0.0, float(maxRayMarchSteps)));

    float vL = 0.0;
    float total_extinction = 1.0;


    float shadowStep = 200.0;
    float3 dV_Sun = sunLocalDir * shadowStep;

    // float mult = length(dV_view);
    float mult = distance(trace_localStart, trace_localEnd) / float(maxIT_clouds);

    float3 color = 0.0;

    total_extinction = 1.0;
    float SdotV = dot(sunViewDir, viewDir);
    float SdotV01 = SdotV*0.5+0.5;

    float mieDay = lerp(phaseg(SdotV, cloudMieG), phaseg(SdotV, cloudMieG2), 0.1);
    float mieDayMulti = phaseg(SdotV, 0.2);

    float mieNight = lerp(phaseg(-SdotV, cloudMieG), phaseg(-SdotV, cloudMieG2), 0.1);
    float mieNightMulti = phaseg(-SdotV, 0.2);

    float3 sunContribution = mieDay * SunColor;
    float3 sunContributionMulti = mieDayMulti * SunColor;
    float3 moonContribution = mieNight * MoonColor;
    float3 moonContributionMulti = mieNightMulti * MoonColor;

    for (int i = 0; i < maxIT_clouds; i++) {
        float stepF = (i + dither) / float(maxIT_clouds);
        float3 trace_localPos = lerp(trace_localStart, trace_localEnd, stepF);

        float3 trace_skyPos = planet.getSkyPosition(trace_localPos);
        float cloud = getCloudDensity(trace_localPos, trace_skyPos, cloud_LevelOfDetail);

        if (cloud > 0.0001) {
            float muS = cloud * cloudDensity;
            float muE =	cloud * cloudDensity;

            float muEshD = 0.0;
            if (sunContribution.g > 1e-5) {
                for (int j = 0; j < 8; j++) {
                    float3 shadowSamplePos = trace_localPos + dV_Sun * (j+0.5);
                    float3 shadow_skyPos = planet.getSkyPosition(shadowSamplePos);
                    float alt_km = planet.getSkyAltitude(shadow_skyPos);

                    // TODO: replace with altitude check
                    if (alt_km < maxHeight*0.001) {
                        float cloudS = getCloudDensity(shadowSamplePos, shadow_skyPos, cloud_ShadowLevelOfDetail);
                        muEshD += cloudS * cloudDensity * shadowStep;
                    }
                }
            }

            float muEshN = 0.0;
            if (moonContribution.g > 1e-5) {
                for (int j = 0; j < 8; j++) {
                    float3 shadowSamplePos = trace_localPos - dV_Sun * (j+0.5);
                    float3 shadow_skyPos = planet.getSkyPosition(shadowSamplePos);
                    float alt_km = planet.getSkyAltitude(shadow_skyPos);

                    // TODO: replace with altitude check
                    if (alt_km < maxHeight*0.001) {
                        float cloudS = getCloudDensity(shadowSamplePos, shadow_skyPos, cloud_ShadowLevelOfDetail);
                        muEshN += cloudS * cloudDensity * shadowStep;
                    }
                }
            }

            // fake multiple scattering approx 2  (from horizon zero down clouds)
            float altitude_KM = planet.getSkyAltitude(trace_skyPos);

            // float h = 0.35 - 0.35 * saturate((trace_localPos.y + ap.camera.position.y - 1500.0) / 4000.0);
            float h = 0.35 - 0.35 * saturate((altitude_KM - 1.5) / 4.0);
            float powder = 1.0 - exp(muE * -400);

            float sunShadowMulti = exp(-log(muEshD*0.15 + 0.5)) * powder;
            float sunShadow = exp(-muEshD);

            float moonShadow = exp(-muEshN);
            float moonShadowMulti = exp(-log(muEshN*0.15 + 0.5)) * powder;

            float ambientPowder = lerp(1.0, powder, h) * (1.0 - h);

            float3 sunLight = sunContribution * sunShadow + sunShadowMulti * sunContributionMulti;
            sunLight *= planet.sampleTransmit(trace_skyPos, sunLocalDir);

            float3 moonLight = moonContribution * moonShadow + moonShadowMulti * moonContributionMulti;
            moonLight *= planet.sampleTransmit(trace_skyPos, moonLocalDir);

            float3 skyCol0 = planet.sampleMultiScatter(trace_skyPos, sunLocalDir);
            float3 S = sunLight + moonLight + skyCol0 * ambientPowder;

            float3 Sint = (S - S * exp(-mult*muE)) / (muE);
            color += muS * Sint * total_extinction;
            total_extinction *= exp(-muE*mult);

            if (total_extinction < 1e-5) break;
        }

        // progress_view += dV_view;
    }

    return float4(color, saturate(total_extinction));
}
