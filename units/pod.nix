{
  lib',
  config,
  lib,
  ...
}:
{
  options = {
    podConfig = lib'.mkQuadletSectionOption {
      anchor = "pod-units-pod";
      description = "The systemd pod configuration (the `[Pod]` section)";
    };
  };
  config = {
    ref = "${config.name}.pod";
    serviceName = lib.defaultTo "${config.name}-pod" (config.podConfig.ServiceName or null);
    podmanName = lib.defaultTo "systemd-${config.name}" (config.podConfig.PodName or null);
    unitConfig = {
      Description = "Podman pod ${config.name}";
      StartLimitBurst = lib.mkDefault 3;
      StartLimitIntervalSec = lib.mkDefault 600;
    };
    serviceConfig = {
      Restart = lib.mkDefault "on-failure";
      RestartSec = lib.mkDefault 5;
      TimeoutStartSec = lib.mkDefault 900;
    };

    finalConfig.Pod = config.podConfig;
  };
}
