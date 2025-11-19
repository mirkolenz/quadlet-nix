{
  lib',
  config,
  lib,
  ...
}:
{
  options = {
    podConfig = lib'.mkSectionOption {
      description = "The systemd pod configuration";
    };
  };
  config = {
    ref = "${config.name}.pod";
    serviceName = config.podConfig.ServiceName or "${config.name}-pod";
    podmanName = config.podConfig.PodName or "systemd-${config.name}";
    unitConfig.Description = "Podman pod ${config.name}";
    serviceConfig = {
      Restart = "always";
      TimeoutStartSec = lib.mkDefault 900;
    };

    finalConfig.Pod = config.podConfig;
  };
}
