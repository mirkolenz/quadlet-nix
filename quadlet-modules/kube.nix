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
    serviceName = "${config.name}-kube";
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman kube ${config.name}";
    serviceConfig = {
      Restart = "always";
      TimeoutStartSec = lib.mkDefault 900;
    };

    finalConfig.Kube = config.kubeConfig;
  };
}
