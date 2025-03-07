{ lib, config, ... }:
let
  inherit (lib) types;
  cfg = config.virtualisation.quadlet;

  duplicateNames = lib.intersectLists (lib.attrNames cfg.containers) (lib.attrNames cfg.pods);
  concatObjects = lib.concatMap lib.attrValues [
    cfg.containers
    cfg.networks
    cfg.pods
    cfg.kubes
    cfg.volumes
    cfg.builds
    cfg.images
  ];
in
{
  options = {
    virtualisation.quadlet = {
      enable = lib.mkEnableOption "quadlet";
      autoUpdate = {
        enable = lib.mkEnableOption "quadlet auto update";
        startAt = lib.mkOption {
          type = types.str;
          default = "*-*-* 00:00:00";
          description = "The time to start the auto update";
        };
      };
      allObjects = lib.mkOption {
        internal = true;
        readOnly = true;
        default = lib.filter (x: x.enable) concatObjects;
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
