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
    kind = "pod";
    longRunning = true;
    serviceName = lib.defaultTo "${config.name}-pod" (config.podConfig.ServiceName or null);
    podmanName = lib.defaultTo "systemd-${config.name}" (config.podConfig.PodName or null);

    finalConfig.Pod = config.podConfig;
  };
}
