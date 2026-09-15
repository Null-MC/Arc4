import aperture;
import settings;
import object_shader;
import lib.octohedral;


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
    uint data;
}


struct DeferShader : Shader<VertexData, FragmentData> {
    static void emitVertex(Vertex input, ObjectTransforms transforms, out VertexData output, out float4 clipPos) {
        output.uv = input.uv();
        output.pos = input.pos().xyz;
        output.color = input.color();

        output.normal = input.normal()
            .orElse(ap.camera.viewInv[3].xyz);

        float4 tangent = input.tangent().orElse(0.0);
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

        if (let texAlbedo = objectData.albedo()) {
            color *= half4(texAlbedo.sampleTexture(input.uv));
        }

        ap.discardCutout(color);

        float3 geo_normal = normalize(input.normal);
        float3 geo_tangent = normalize(input.tangent);
        float3 tex_normal = geo_normal;

        if (let texNormalMap = objectData.normal()) {
            half4 normalData = half4(texNormalMap.sampleTexture(input.uv));

            float3x3 tbn;
            tbn[0] = geo_tangent;
            tbn[1] = cross(geo_tangent, geo_normal) * sign(input.tangent_w);
            tbn[2] = geo_normal;

            tex_normal.xy = normalData.xy * 2.0 - 1.0;
            tex_normal.z = sqrt(1.0 - dot(tex_normal.xy, tex_normal.xy));
            tex_normal = mul(tex_normal, tbn);
        }

        half4 specular = 0.0h;
        if (let texSpecularMap = objectData.specular()) {
            specular = half4(texSpecularMap.sampleTexture(input.uv));
        }

        if (!IsTranslucent) color.a = 1.0h;

        FragmentData output;
        output.color = color;
        output.normal.xy = octohedral::encode(half3(geo_normal));
        output.normal.zw = octohedral::encode(half3(tex_normal));
        output.specular = specular;
        output.data = input.blockId;
        return output;
    }
}
