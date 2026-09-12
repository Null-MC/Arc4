public module scene_buffer;


ConstantBuffer<SceneBuffer, ScalarDataLayout> scene;

struct SceneBuffer {
    public float2 TAA_jitter;
};
