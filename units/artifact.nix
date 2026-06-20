{
  config,
  lib',
  lib,
  ...
}:
{
  options = {
    artifactConfig = lib'.mkQuadletSectionOption {
      anchor = "artifact-units-artifact";
      description = ''
        The systemd artifact configuration (the `[Artifact]` section)

        WARNING: Experimental Unit. This unit is considered experimental and still in development. Inputs, options, and outputs are all subject to change.
      '';
    };
  };
  config = {
    ref = "${config.name}.artifact";
    serviceName = lib.defaultTo "${config.name}-artifact" (config.artifactConfig.ServiceName or null);
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman artifact ${config.name}";

    finalConfig.Artifact = config.artifactConfig;
  };
}
