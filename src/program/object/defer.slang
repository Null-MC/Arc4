import aperture;
import settings;
import object_shader;
import lib.common;
import lib.octohedral;
import lib.ray_cone;


extern static const bool IsTranslucent = false;

struct VertexData {
    float4 color : COLOR;
    float2 uv : TEXCOORD;
    float3 normal;
    float3 tangent;
    nointerpolation float tangent_w;
    float3 pos;
    nointerpolation uint blockId;
}

struct FragmentData {
    half4 color;
    half4 normal;
    half4 specular;
    uint2 data;
}


struct DeferShader : Shader<VertexData, FragmentData> {
    static void emitVertex(Vertex input, ObjectTransforms transforms, out VertexData output, out float4 clipPos) {
        output.uv = input.uv();
        output.pos = input.pos().xyz;
        output.color = input.color();

        output.normal = input.normal()
            .orElse(ap.camera.viewInv[3].xyz);

        float4 tangent = input.tangent().orElse(float4(0,0,0,1));
        output.tangent = tangent.xyz;
        output.tangent_w = tangent.w;

        float4 viewPos = mul(transforms.view, input.pos());
        clipPos = mul(transforms.projection, viewPos);

        if (userSettings.TAA_Enabled) {
            clipPos.xy += scene.TAA_jitter * (2.0 * clipPos.w);
        }

        if (let block = input.blockID()) {
            output.blockId = block.data.customId;
        }
        else {
            output.blockId = 0u;
        }
    }

    static FragmentData shadeSurface(PixelData objectData, VertexData input) {
        half4 color = half4(input.color);
        half fWidth = 0.0h;
        float lod = 0.0;

        if (let texAlbedo = objectData.albedo()) {
            lod = texAlbedo.getLOD(input.uv);
            lod = max(lod + SamplingBias, 0.0);

            color *= half4(texAlbedo.sampleLevel(input.uv, lod));

            int3 size = texAlbedo.getSize();
            // float2 dX = ddx(input.uv) * size.xy;
            // float2 dY = ddy(input.uv) * size.xy;
            // fWidth = half(sqrt(max(dot(dX, dX), dot(dY, dY))));
            fWidth = half(RayCone.CreateFromRaster(input.uv, size.xy).width);
        }

        ap.discardCutout(color);

        float3 geo_normal = normalize(input.normal);
        float3 geo_tangent = normalize(input.tangent);
        float3 tex_normal = geo_normal;

        if (let texNormalMap = objectData.normal()) {
            if (any(input.tangent != 0.0)) {
                float4 normalData = texNormalMap.sampleLevel(input.uv, lod);

                if (any(normalData.xy != 1.0)) {
                    float3x3 tbn;
                    tbn[0] = geo_tangent;
                    // tbn[1] = cross(geo_tangent, geo_normal) * sign(input.tangent_w);
                    tbn[1] = cross(geo_tangent, geo_normal) * (input.tangent_w >= 0.0 ? 1.0 : -1.0);
                    tbn[2] = geo_normal;

                    tex_normal.xy = normalData.xy * 2.0 - 1.0;
                    tex_normal.z = sqrt(1.0 - saturate(dot(tex_normal.xy, tex_normal.xy)));
                    tex_normal = mul(tex_normal, tbn);
                }
            }
        }

        half4 specular = 0.0h;
        if (let texSpecularMap = objectData.specular()) {
            specular = half4(texSpecularMap.sampleLevel(input.uv, lod));
        }

        if (input.blockId == 1) {
            // water
            color = 0.0h;
            tex_normal = geo_normal;
            specular = half4(1.0h, 0.02h, 0.0h, 0.0h);
        }

        if (!IsTranslucent) color.a = 1.0h;

        FragmentData output;
        output.color = color;
        output.normal.xy = octohedral::encode(half3(geo_normal));
        output.normal.zw = octohedral::encode(half3(tex_normal));
        output.specular = specular;
        output.data = uint2(input.blockId, asuint16(fWidth));
        return output;
    }
}
