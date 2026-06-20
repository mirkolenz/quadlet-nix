{
  lib',
  config,
  lib,
  ...
}:
{
  options = {
    kubeConfig = lib'.mkQuadletSectionOption {
      anchor = "kube-units-kube";
      description = "The systemd kube configuration (the `[Kube]` section)";
    };
  };
  config = {
    ref = "${config.name}.kube";
    serviceName = lib.defaultTo "${config.name}" (config.kubeConfig.ServiceName or null);
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
