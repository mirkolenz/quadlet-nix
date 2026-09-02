{
  lib,
  config,
  lib',
  podman,
  writeShellApplication,
  ...
}:
{
  options = {
    containerConfig = lib'.mkQuadletSectionOption {
      anchor = "container-units-container";
      description = "The systemd container configuration (the `[Container]` section)";
    };
    imageFile = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "The image file to load before starting the service";
    };
    imageStream = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "The image stream to load before starting the service";
    };
  };
  config =
    let
      prestart = writeShellApplication {
        name = "prestart";
        text = ''
          ${lib.optionalString (config.imageFile != null) ''
            ${lib.getExe podman} load -i ${config.imageFile}
          ''}
          ${lib.optionalString (config.imageStream != null) ''
            ${config.imageStream} | ${lib.getExe podman} load
          ''}
        '';
      };
    in
    {
      kind = "container";
      longRunning = true;
      serviceName = lib.defaultTo "${config.name}" (config.containerConfig.ServiceName or null);
      podmanName = lib.defaultTo "systemd-${config.name}" (config.containerConfig.ContainerName or null);
      containerConfig = lib.mkMerge [
        (lib.mkIf (config.imageFile != null) {
          Image = "localhost/${config.imageFile.imageName}:${config.imageFile.imageTag}";
          AutoUpdate = "disabled";
        })
        (lib.mkIf (config.imageStream != null) {
          Image = "localhost/${config.imageStream.imageName}:${config.imageStream.imageTag}";
          AutoUpdate = "disabled";
        })
      ];
      serviceConfig.ExecStartPre = [ (lib.getExe prestart) ];

      finalConfig.Container = config.containerConfig;
    };
}
