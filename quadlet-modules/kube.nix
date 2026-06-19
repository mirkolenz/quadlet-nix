{
  lib',
  config,
  lib,
  ...
}:
{
  options = {
    kubeConfig = lib'.mkSectionOption {
      description = "The systemd kube configuration";
    };
  };
  config = {
    ref = "${config.name}.kube";
    serviceName = lib.defaultTo "${config.name}" config.kubeConfig.ServiceName;
    podmanName = "systemd-${config.name}";
    unitConfig = {
      Description = "Podman kube ${config.name}";
      StartLimitBurst = lib.mkDefault 3;
      StartLimitIntervalSec = lib.mkDefault 600;
    };
    serviceConfig = {
      Restart = lib.mkDefault "on-failure";
      RestartSec = lib.mkDefault 5;
      TimeoutStartSec = lib.mkDefault 900;
    };

    finalConfig.Kube = config.kubeConfig;
  };
}
