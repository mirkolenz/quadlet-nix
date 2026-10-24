{
  config,
  lib',
  lib,
  ...
}:
{
  options = {
    imageConfig = lib'.mkQuadletSectionOption {
      anchor = "image-units-image";
      description = "The systemd image configuration (the `[Image]` section)";
    };
  };
  config = {
    kind = "image";
    serviceName = lib.defaultTo "${config.name}-image" (config.imageConfig.ServiceName or null);
    # What Quadlet resolves `Image=<name>.image` to.
    podmanName = config.imageConfig.ImageTag or config.imageConfig.Image or null;

    finalConfig.Image = config.imageConfig;
  };
}
