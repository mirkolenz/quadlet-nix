{ lib, config, ... }:
let
  inherit (lib) types;
  cfg = config.virtualisation.quadlet;

  duplicateNames = lib.intersectLists (lib.attrNames cfg.containers) (lib.attrNames cfg.pods);
in
{
  options = {
    virtualisation.quadlet = {
      enable = lib.mkEnableOption "quadlet";
      autoUpdate = {
        enable = lib.mkOption {
          type = types.bool;
          default = true;
        };
        startAt = lib.mkOption {
          type = types.str;
          default = "*-*-* 00:00:00";
        };
      };
      allObjects = lib.mkOption {
        internal = true;
        readOnly = true;
        default = lib.concatMap lib.attrValues [
          cfg.containers
          cfg.networks
          cfg.pods
          cfg.kubes
          cfg.volumes
          cfg.builds
          cfg.images
        ];
      };
    };
  };
  config = lib.mkIf (cfg.enable && lib.length cfg.allObjects > 0) {
    assertions =
      [
        {
          assertion = duplicateNames == [ ];
          message = ''
            The container/pod names should be unique!
            See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html#podname
            The following names are not unique: ${lib.concatStringsSep " " duplicateNames}
          '';
        }
      ]
      ++ (map (obj: {
        assertion = obj.imageFile == null || obj.imageStream == null;
        message = "Only one of imageFile and imageStream can be set for container ${obj.name}";
      }) (lib.attrValues cfg.containers));
  };
}
