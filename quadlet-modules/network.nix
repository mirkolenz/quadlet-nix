{
  config,
  lib',
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

    finalConfig.Network = config.networkConfig;
  };
}
