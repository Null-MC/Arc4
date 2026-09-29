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

    public ComputeShaderBuilder dispatchRenderSize(int localSizeX, int localSizeY) {
        var sizeX = (int)Math.ceil(screen.renderWidth() / (float)localSizeX);
        var sizeY = (int)Math.ceil(screen.renderHeight() / (float)localSizeY);

        shader.dispatch2D(sizeX, sizeY);
        return this;
    }

    public ComputeShaderBuilder overrideObject(String name, RWTexture texture) {
        shader.overrideObject(name, texture.name());
        return this;
    }

    public ComputeShaderBuilder exportInt(String name, int value) {
        shader.exportInt(name, value);
        return this;
    }
}
