{
  config,
  lib',
  lib,
  ...
}:
{
  options = {
    imageConfig = lib'.mkSectionOption {
      description = "The systemd image configuration";
    };
  };
  config = {
    ref = "${config.name}.image";
    serviceName = lib.defaultTo "${config.name}-image" config.imageConfig.ServiceName;
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman image ${config.name}";

    finalConfig.Image = config.imageConfig;
  };
}
