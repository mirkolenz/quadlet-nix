{
  config,
  lib',
  lib,
  ...
}:
let
  inherit (lib') mkQuadletOption singleOrList keyValue;
  inherit (lib.types)
    str
    int
    bool
    either
    ;
in
{
  options = {
    volumeConfig = lib'.mkQuadletSectionOption {
      anchor = "volume-units-volume";
      description = "The systemd volume configuration (the `[Volume]` section)";
      options = {
        ContainersConfModule = mkQuadletOption {
          type = singleOrList str;
          flag = "--module";
          example = [ "/etc/nvd.conf" ];
        };
        Copy = mkQuadletOption {
          type = bool;
          default = true;
        };
        Device = mkQuadletOption {
          type = str;
          example = "tmpfs";
        };
        Driver = mkQuadletOption {
          type = str;
          flag = "--driver";
          example = "image";
        };
        GlobalArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--log-level=debug" ];
        };
        Group = mkQuadletOption {
          type = either int str;
          example = 192;
        };
        Image = mkQuadletOption {
          type = str;
          example = "quay.io/centos/centos:latest";
        };
        Label = mkQuadletOption {
          type = keyValue;
          example = {
            foo = "bar";
          };
        };
        Options = mkQuadletOption {
          type = str;
          example = "nodev,noexec";
        };
        PodmanArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--driver=image" ];
        };
        ServiceName = mkQuadletOption {
          type = str;
          example = "name";
        };
        Type = mkQuadletOption {
          type = str;
          example = "ext4";
        };
        User = mkQuadletOption {
          type = either int str;
          example = 123;
        };
        VolumeName = mkQuadletOption {
          type = str;
          example = "foo";
        };
      };
    };
  };
  config = {
    ref = "${config.name}.volume";
    serviceName = lib.defaultTo "${config.name}-volume" config.volumeConfig.ServiceName;
    podmanName = lib.defaultTo "systemd-${config.name}" config.volumeConfig.VolumeName;
    unitConfig.Description = "Podman volume ${config.name}";

    finalConfig.Volume = config.volumeConfig;
  };
}
