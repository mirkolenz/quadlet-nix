{
  config,
  lib',
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
    serviceName = "${config.name}-build";
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman build ${config.name}";

    finalConfig.Build = config.buildConfig;
  };
}
