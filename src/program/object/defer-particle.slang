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
    float3 pos;
}

struct FragmentData {
    half4 color;
    half4 normal;
    half4 specular;
    uint2 data;
}


struct ObjectShader : Shader<VertexData, FragmentData> {
    static void emitVertex(Vertex input, ObjectTransforms transforms, out VertexData output, out float4 clipPos) {
        output.uv = input.uv();
        output.pos = input.pos().xyz;
        output.color = input.color();

        output.normal = input.normal()
            .orElse(ap.camera.viewInv[3].xyz);

        float4 viewPos = mul(transforms.view, input.pos());
        clipPos = mul(transforms.projection, viewPos);

        if (userSettings.TAA_Enabled) {
            clipPos.xy += scene.TAA_jitter * (2.0 * clipPos.w);
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

        // ap.discardCutout(color);
        if (color.a < .004) discard;

        float3 geo_normal = normalize(input.normal);

        half4 specular = 0.0h;
        if (let texSpecularMap = objectData.specular()) {
            specular = half4(texSpecularMap.sampleLevel(input.uv, lod));
        }

        if (!IsTranslucent) color.a = 1.0h;

        FragmentData output;
        output.color = color;
        output.normal.xy = octohedral::encode(half3(geo_normal));
        output.normal.zw = octohedral::encode(half3(geo_normal));
        output.specular = specular;
        output.data = uint2(0u, asuint16(fWidth));
        return output;
    }
}
