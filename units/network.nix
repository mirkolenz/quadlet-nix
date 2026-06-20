{
  config,
  lib',
  podman,
  lib,
  ...
}:
{
  options = {
    networkConfig = lib'.mkQuadletSectionOption {
      anchor = "network-units-network";
      description = "The systemd network configuration (the `[Network]` section)";
    };
  };
  config = {
    ref = "${config.name}.network";
    serviceName = lib.defaultTo "${config.name}-network" (config.networkConfig.ServiceName or null);
    podmanName = lib.defaultTo "systemd-${config.name}" (config.networkConfig.NetworkName or null);
    unitConfig.Description = "Podman network ${config.name}";
    serviceConfig = lib.mkIf (lib.versionOlder podman.version "5.5") {
      ExecStopPost = "${lib.getExe podman} network rm ${config.podmanName}";
    };
    networkConfig = lib.mkIf (lib.versionAtLeast podman.version "5.5") {
      NetworkDeleteOnStop = true;
    };

    finalConfig.Network = config.networkConfig;
  };
}
