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
    containerConfig = lib'.mkSectionOption {
      description = "The systemd container configuration";
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
      ref = "${config.name}.container";
      serviceName = "${config.name}";
      podmanName = config.containerConfig.ContainerName or "systemd-${config.name}";
      containerConfig = lib.mkMerge [
        (lib.mkIf (config.imageFile != null) {
          Image = "localhost/${config.imageFile.imageName}:${config.imageFile.imageTag}";
          AutoUpdate = null;
        })
        (lib.mkIf (config.imageStream != null) {
          Image = "localhost/${config.imageStream.imageName}:${config.imageStream.imageTag}";
          AutoUpdate = null;
        })
      ];
      unitConfig.Description = "Podman container ${config.name}";
      serviceConfig = {
        Restart = "always";
        TimeoutStartSec = lib.mkDefault 900;
        ExecStartPre = [ (lib.getExe prestart) ];
      };

      finalConfig.Container = config.containerConfig;
    };
}
