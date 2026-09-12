import aperture;
import object_shader;
import settings;

// import helpers.shadows;


struct VertexData {
    float4 color : COLOR;
    float2 uv : TEXCOORD;
    float3 pos;
}

struct FragmentData {
    float4 color;
}


struct BasicShader : Shader<VertexData, FragmentData> {
    static void emitVertex(Vertex input, ObjectTransforms transforms, out VertexData output, out float4 clipPos) {
        output.uv = input.uv();
        output.pos = input.pos().xyz;
        output.color = input.color();

        float4 viewPos = mul(transforms.view, input.pos());
        clipPos = mul(transforms.projection, viewPos);
    }

    static FragmentData shadeSurface(PixelData objectData, VertexData input) {
        float4 color = input.color;

        if (let texAlbedo = objectData.albedo()) {
            color *= texAlbedo.sampleTexture(input.uv);
        }

        ap.discardCutout(color);

        color.rgb = pow(color.rgb, half3(2.2));

        // if (userSettings.shadows) {
        //     color.rgb *= lerp(0.35, 1.0, shadowVisibility(input.pos));
        // }

        FragmentData output;
        output.color = color;
        return output;
    }
}
