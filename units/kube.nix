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
    # The objects are named in the YAML files, which `podman kube down` takes.
    podmanName = lib.mapNullable (yaml: lib.concatStringsSep " " (lib.toList yaml)) (
      config.kubeConfig.Yaml or null
    );

    finalConfig.Kube = config.kubeConfig;
  };
}
