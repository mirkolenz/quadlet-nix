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
    containerConfig = lib'.mkUnitOption { };
    imageFile = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
    };
    imageStream = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
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
        })
        (lib.mkIf (config.imageStream != null) {
          Image = "localhost/${config.imageStream.imageName}:${config.imageStream.imageTag}";
        })
      ];
      unitConfig.Description = "Podman container ${config.name}";
      serviceConfig.ExecStartPre = [ (lib.getExe prestart) ];

      systemdConfig.Container = config.containerConfig;
    };
}
