{
  lib',
  config,
  ...
}:
{
  options = {
    podConfig = lib'.mkUnitOption { };
  };
  config = {
    ref = "${config.name}.pod";
    serviceName = "${config.name}-pod";
    podmanName = config.podConfig.PodName or "systemd-${config.name}";
    unitConfig.Description = "Podman pod ${config.name}";

    systemdConfig.Pod = config.podConfig;
  };
}
