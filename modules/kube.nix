{
  lib',
  config,
  ...
}:
{
  options = {
    kubeConfig = lib'.mkUnitOption { };
  };
  config = {
    ref = "${config.name}.kube";
    serviceName = "${config.name}-kube";
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman kube ${config.name}";

    systemdConfig.Kube = config.kubeConfig;
  };
}
