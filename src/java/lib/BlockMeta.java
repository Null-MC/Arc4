package lib;

import java.util.HashMap;

import dev.irisshaders.aperture.api.objects.IBlockState;


public class BlockMeta {
    public String path;
    public HashMap<String, String> properties = new HashMap<>();


    public BlockMeta() {}

    public boolean matches(IBlockState block) {
        if (!block.matches(path)) return false;

        for (var propertyName : properties.keySet()) {
            var actualValue = block.getProperty(propertyName);
            if (actualValue.isEmpty()) return false;

            var expectedValue = properties.get(propertyName);
            if (!actualValue.get().equals(expectedValue)) return false;
        }

        return true;
    }

    public static BlockMeta parse(String resourceId) {
        var meta = new BlockMeta();

        var propertyStart = resourceId.indexOf('[');
        if (propertyStart >= 0) {
            var propertyEnd = resourceId.indexOf(']');
            if (propertyEnd < 0) throw new IllegalArgumentException("Malformed resource ID: missing closing bracket for properties");

            meta.path = resourceId.substring(0, propertyStart);

            var propertiesString = resourceId.substring(propertyStart + 1, propertyEnd);
            var propertiesArray = propertiesString.split(",");

            for (var property : propertiesArray) {
                var keyValue = property.split("=");
                if (keyValue.length != 2) throw new IllegalArgumentException("Malformed property: " + property);

                meta.properties.put(keyValue[0], keyValue[1]);
            }
        }
        else {
            meta.path = resourceId;
        }

        // TODO: auto prepend minecraft: if no namespace is present?

        return meta;
    }
}
