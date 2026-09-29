package pipeline;

public class LightData {
    private final int data;

    
    public LightData(int data) {
        this.data = data;
    }

    public int data() {
        return data;
    }

    public static LightData fromHexColor(String hex_color, int range) {
        String cleanHex = hex_color.replace("#", "");
        int rgb = Integer.parseInt(cleanHex, 16) & 0xFFFFFF;
        
        int r = (rgb >> 16) & 0xFF;
        int g = (rgb >> 8) & 0xFF;
        int b = rgb & 0xFF;
        int a = range & 0xFF;

        int packed = r | (g << 8) | (b << 16) | (a << 24);
        return new LightData(packed);
    }
}
