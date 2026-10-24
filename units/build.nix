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
    kind = "build";
    serviceName = lib.defaultTo "${config.name}-build" (config.buildConfig.ServiceName or null);
    podmanName = lib.mapNullable (tags: lib.head (lib.toList tags)) (
      config.buildConfig.ImageTag or null
    );

    finalConfig.Build = config.buildConfig;
  };
}
