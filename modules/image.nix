{
  config,
  lib',
  ...
}:
{
  options = {
    imageConfig = lib'.mkUnitOption { };
  };
  config = {
    ref = "${config.name}.image";
    serviceName = "${config.name}-image";
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman image ${config.name}";

    systemdConfig.Volume = config.imageConfig;
  };
}
