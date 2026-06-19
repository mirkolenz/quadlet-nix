{
  config,
  lib',
  lib,
  ...
}:
{
  options = {
    volumeConfig = lib'.mkSectionOption {
      description = "The systemd volume configuration";
    };
  };
  config = {
    ref = "${config.name}.volume";
    serviceName = lib.defaultTo "${config.name}-volume" config.volumeConfig.ServiceName;
    podmanName = lib.defaultTo "systemd-${config.name}" config.volumeConfig.VolumeName;
    unitConfig.Description = "Podman volume ${config.name}";

    finalConfig.Volume = config.volumeConfig;
  };
}
