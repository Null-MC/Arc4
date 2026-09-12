import aperture;
import object_shader;


struct vIn {
    float2 uv : TEXCOORD;
}

struct vOut {}

struct ShadowShader : Shader<vIn, vOut> {
    static void emitVertex(Vertex input, ObjectTransforms transforms, out vIn output, out float4 clipPos) {
		output.uv = input.uv();

        float4 viewPos = mul(transforms.view, input.pos());
		clipPos = mul(transforms.projection, viewPos);
    }

    static vOut shadeSurface(PixelData objectData, vIn input) {
        vOut output = vOut();

        if (let texture = objectData.albedo()) {
            ap.discardCutout(texture.sampleTexture(input.uv));
        }

        return output;
    }
}
