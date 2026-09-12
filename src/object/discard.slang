import aperture;
import object_shader;


struct VertexData {};

struct FragmentData {};


struct DiscardShader : Shader<VertexData, FragmentData> {
    static void emitVertex(Vertex input, ObjectTransforms transforms, out VertexData output, out float4 clipPos) {
        clipPos = float4(-10.0);
    }

    static FragmentData shadeSurface(PixelData objectData, VertexData input) {
        return FragmentData();
    }
}
