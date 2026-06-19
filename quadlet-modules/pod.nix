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
    serviceName = lib.defaultTo "${config.name}-pod" config.podConfig.ServiceName;
    podmanName = lib.defaultTo "systemd-${config.name}" config.podConfig.PodName;
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
