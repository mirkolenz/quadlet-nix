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
    ref = "${config.name}.image";
    serviceName = lib.defaultTo "${config.name}-image" (config.imageConfig.ServiceName or null);
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman image ${config.name}";

    finalConfig.Image = config.imageConfig;
  };
}
