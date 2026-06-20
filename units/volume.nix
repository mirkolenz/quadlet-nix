{
  config,
  lib',
  lib,
  ...
}:
{
  options = {
    volumeConfig = lib'.mkQuadletSectionOption {
      anchor = "volume-units-volume";
      description = "The systemd volume configuration (the `[Volume]` section)";
    };
  };
  config = {
    ref = "${config.name}.volume";
    serviceName = lib.defaultTo "${config.name}-volume" (config.volumeConfig.ServiceName or null);
    podmanName = lib.defaultTo "systemd-${config.name}" (config.volumeConfig.VolumeName or null);
    unitConfig.Description = "Podman volume ${config.name}";

    finalConfig.Volume = config.volumeConfig;
  };
}
