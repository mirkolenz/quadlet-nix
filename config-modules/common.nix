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
      reloadUserServices = lib.mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to emit a per-UID system-level reloader service that runs
          `daemon-reload` and `try-restart` on the user's systemd manager when
          the generated rootless quadlet units change.

          Without this, `nixos-rebuild switch` updates unit files on disk but
          the running `systemd --user` instance keeps the old containers going
          until manually restarted.
        '';
      };
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
