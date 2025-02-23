{
  config,
  lib',
  podman,
  lib,
  ...
}:
{
  options = {
    networkConfig = lib'.mkSectionOption {
      description = "The systemd network configuration";
    };
  };
  config = {
    ref = "${config.name}.network";
    serviceName = "${config.name}-network";
    podmanName = config.networkConfig.NetworkName or "systemd-${config.name}";
    unitConfig.Description = "Podman network ${config.name}";
    serviceConfig = {
      ExecStop = "${lib.getExe podman} network rm ${config.podmanName}";
    };

    finalConfig.Network = config.networkConfig;
  };
}
