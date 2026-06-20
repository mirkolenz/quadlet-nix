{
  config,
  lib',
  lib,
  ...
}:
{
  options = {
    buildConfig = lib'.mkQuadletSectionOption {
      anchor = "build-units-build";
      description = "The systemd build configuration (the `[Build]` section)";
    };
  };
  config = {
    ref = "${config.name}.build";
    serviceName = lib.defaultTo "${config.name}-build" (config.buildConfig.ServiceName or null);
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman build ${config.name}";

    finalConfig.Build = config.buildConfig;
  };
}
