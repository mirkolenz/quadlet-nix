{
  config,
  lib',
  ...
}:
{
  options = {
    artifactConfig = lib'.mkSectionOption {
      description = "The systemd artifact configuration";
    };
  };
  config = {
    ref = "${config.name}.artifact";
    serviceName = "${config.name}-artifact";
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman artifact ${config.name}";

    finalConfig.Artifact = config.artifactConfig;
  };
}
