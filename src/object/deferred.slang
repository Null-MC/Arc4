import aperture;
import settings;
import lib.scene;
import object_shader;
import lib.octohedral;


struct VertexData {
    float4 color : COLOR;
    float2 uv : TEXCOORD;
    float3 normal;
    float3 pos;
}

struct FragmentData {
    float4 color;
    float2 normal;
}


struct DeferShader : Shader<VertexData, FragmentData> {
    static void emitVertex(Vertex input, ObjectTransforms transforms, out VertexData output, out float4 clipPos) {
        output.uv = input.uv();
        output.pos = input.pos().xyz;
        output.color = input.color();
        output.normal = input.normal().orElse(ap.camera.viewInv[3].xyz);

        float4 viewPos = mul(transforms.view, input.pos());
        clipPos = mul(transforms.projection, viewPos);

        if (userSettings.TAA_Enabled) {
            clipPos.xy += scene.TAA_jitter * (2.0 * clipPos.w);
        }
    }

    static FragmentData shadeSurface(PixelData objectData, VertexData input) {
        float4 color = input.color;

        if (let texAlbedo = objectData.albedo()) {
            color *= texAlbedo.sampleTexture(input.uv);
        }

        ap.discardCutout(color);

        float3 normal = normalize(input.normal);

        FragmentData output;
        output.color = color;
        output.normal = octohedral::encode(half3(normal));
        return output;
    }
}
