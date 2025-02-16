{
  config,
  lib',
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
    serviceName = "${config.name}-volume";
    podmanName = config.volumeConfig.VolumeName or "systemd-${config.name}";
    unitConfig.Description = "Podman volume ${config.name}";

    finalConfig.Volume = config.volumeConfig;
  };
}
