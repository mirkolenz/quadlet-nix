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
    kind = "kube";
    longRunning = true;
    serviceName = lib.defaultTo "${config.name}" (config.kubeConfig.ServiceName or null);
    podmanName = "systemd-${config.name}";

    finalConfig.Kube = config.kubeConfig;
  };
}
