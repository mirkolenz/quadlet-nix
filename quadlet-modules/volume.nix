{
  config,
  lib',
  ...
}:
{
  options = {
    volumeConfig = lib'.mkUnitOption { };
  };
  config = {
    ref = "${config.name}.volume";
    serviceName = "${config.name}-volume";
    podmanName = config.volumeConfig.VolumeName or "systemd-${config.name}";
    unitConfig.Description = "Podman volume ${config.name}";

    systemdConfig.Volume = config.volumeConfig;
  };
}
