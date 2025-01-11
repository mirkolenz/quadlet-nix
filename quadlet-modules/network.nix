{
  config,
  lib',
  ...
}:
{
  options = {
    networkConfig = lib'.mkUnitOption { };
  };
  config = {
    ref = "${config.name}.network";
    serviceName = "${config.name}-network";
    podmanName = config.networkConfig.NetworkName or "systemd-${config.name}";
    unitConfig.Description = "Podman network ${config.name}";

    systemdConfig.Network = config.networkConfig;
  };
}
