{
  lib',
  config,
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
    serviceName = "${config.name}-pod";
    podmanName = config.podConfig.PodName or "systemd-${config.name}";
    unitConfig.Description = "Podman pod ${config.name}";

    finalConfig.Pod = config.podConfig;
  };
}
