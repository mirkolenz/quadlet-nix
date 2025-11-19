{
  config,
  lib',
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
    serviceName = "${config.name}-image";
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman image ${config.name}";

    finalConfig.Image = config.imageConfig;
  };
}
