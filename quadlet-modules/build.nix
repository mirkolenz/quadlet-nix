{
  config,
  lib',
  ...
}:
{
  options = {
    buildConfig = lib'.mkUnitOption {
      description = "The systemd build configuration";
    };
  };
  config = {
    ref = "${config.name}.build";
    serviceName = "${config.name}-build";
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman build ${config.name}";

    systemdConfig.Build = config.buildConfig;
  };
}
