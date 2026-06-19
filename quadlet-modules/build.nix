{
  config,
  lib',
  lib,
  ...
}:
{
  options = {
    buildConfig = lib'.mkSectionOption {
      description = "The systemd build configuration";
    };
  };
  config = {
    ref = "${config.name}.build";
    serviceName = lib.defaultTo "${config.name}-build" config.buildConfig.ServiceName;
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman build ${config.name}";

    finalConfig.Build = config.buildConfig;
  };
}
