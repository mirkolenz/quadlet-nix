{
  config,
  lib',
  ...
}:
{
  options = {
    imageConfig = lib'.mkUnitOption {
      description = "The systemd image configuration";
    };
  };
  config = {
    ref = "${config.name}.image";
    serviceName = "${config.name}-image";
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman image ${config.name}";

    finalConfig.Volume = config.imageConfig;
  };
}
