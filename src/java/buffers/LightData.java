package buffers;

public record LightData(int data) {
    public static LightData fromHexColor(String hex_color, int range) {
        String cleanHex = hex_color.replace("#", "");
        int rgb = Integer.parseInt(cleanHex, 16) & 0xFFFFFF;
        
        int shiftedRange = (range & 0xFF) << 24;
        return new LightData(shiftedRange | rgb);
    }
}
