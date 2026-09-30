package lib.Shader;

import dev.irisshaders.aperture.api.commands.ComputeCommand;
import dev.irisshaders.aperture.api.objects.RWTexture;
import dev.irisshaders.aperture.api.objects.Screen;

public class ComputeShaderBuilder {
    private final ComputeCommand shader;
    private final Screen screen;


    public ComputeShaderBuilder(Screen screen, ComputeCommand shader) {
        this.shader = shader;
        this.screen = screen;
    }

    public ComputeShaderBuilder dispatch3D(int groupsX, int groupsY, int groupsZ) {
        shader.dispatch3D(groupsX, groupsY, groupsZ);
        return this;
    }

    public ComputeShaderBuilder dispatch2D(int groupsX, int groupsY) {
        shader.dispatch2D(groupsX, groupsY);
        return this;
    }

    public ComputeShaderBuilder dispatch2D(int globalSizeX, int globalSizeY, int localSizeX, int localSizeY) {
        shader.dispatch2D(
            (int)Math.ceil(globalSizeX / (float)localSizeX),
            (int)Math.ceil(globalSizeY / (float)localSizeY));
        return this;
    }

    public ComputeShaderBuilder dispatchRenderSize(int localSizeX, int localSizeY) {
        dispatch2D(screen.renderWidth(), screen.renderHeight(), localSizeX, localSizeY);
        return this;
    }

    public ComputeShaderBuilder dispatch1D(int groupsX) {
        shader.dispatch1D(groupsX);
        return this;
    }

    public ComputeShaderBuilder dispatch1D(int globalSizeX, int localSizeX) {
        shader.dispatch1D((int)Math.ceil(globalSizeX / (float)localSizeX));
        return this;
    }

    public ComputeShaderBuilder override(String name, RWTexture texture) {
        shader.overrideObject(name, texture.name());
        return this;
    }

    public ComputeShaderBuilder exportInt(String name, int value) {
        shader.exportInt(name, value);
        return this;
    }
}
