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
    serviceConfig = lib.mkIf (lib.versionOlder podman.version "5.5") {
      ExecStopPost = "${lib.getExe podman} network rm ${config.podmanName}";
    };
    networkConfig = lib.mkIf (lib.versionAtLeast podman.version "5.5") {
      NetworkDeleteOnStop = true;
    };

    finalConfig.Network = config.networkConfig;
  };
}
