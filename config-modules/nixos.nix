{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) types;

  cfg = config.virtualisation.quadlet;
  podman = config.virtualisation.podman.package or pkgs.podman;
  lib' = import ../lib.nix lib;

  mkSubmodule =
    path:
    types.submodule {
      imports = [
        path
        ../quadlet-modules/common.nix
        ../quadlet-modules/nixos.nix
      ];
      _module.args = {
        inherit lib' podman;
        inherit (pkgs) writeShellApplication;
      };
    };

  rootfulObjects = lib.filter (obj: obj.uid == null) cfg.allObjects;
  rootlessObjects = lib.filter (obj: obj.uid != null) cfg.allObjects;
  rootlessUsers = lib.unique (map (obj: obj.uid) rootlessObjects);

  mkAutoUpdate =
    conditionUsers:
    import ./update.nix {
      inherit
        lib
        podman
        conditionUsers
        ;
      inherit (cfg.autoUpdate) startAt;
    };

  mkServiceOverride =
    obj:
    lib.nameValuePair obj.serviceName {
      overrideStrategy = "asDropin";
      inherit (obj)
        aliases
        wantedBy
        requiredBy
        upheldBy
        ;
    };

  mkQuadletUnits =
    type: objects:
    pkgs.runCommand "quadlet-package-${type}"
      {
        QUADLET_UNIT_DIRS = pkgs.symlinkJoin {
          name = "quadlet-directory-${type}";
          paths = map (obj: pkgs.writeTextDir obj.ref obj.text) objects;
        };
      }
      ''
        mkdir -p $out/lib/systemd/${type}/
        ${podman}/lib/systemd/${type}-generators/podman-${type}-generator $out/lib/systemd/${type}/
      '';
in
{
  imports = [ ./common.nix ];
  options = {
    virtualisation.quadlet = {
      generatedUnits = lib.mkOption {
        type = types.package;
        internal = true;
        description = ''
          A package with generated systemd unit files that will be added to `systemd.packages`.
        '';
      };
      containers = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/container.nix);
        default = { };
        description = "The containers to manage";
      };
      networks = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/network.nix);
        default = { };
        description = "The networks to manage";
      };
      pods = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/pod.nix);
        default = { };
        description = "The pods to manage";
      };
      kubes = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/kube.nix);
        default = { };
        description = "The kubes to manage";
      };
      volumes = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/volume.nix);
        default = { };
        description = "The volumes to manage";
      };
      builds = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/build.nix);
        default = { };
        description = "The builds to manage";
      };
      images = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/image.nix);
        default = { };
        description = "The images to manage";
      };
    };
  };

  config = lib.mkIf (cfg.enable && lib.length cfg.allObjects > 0) {
    virtualisation.podman.enable = true;

    virtualisation.quadlet.generatedUnits = pkgs.symlinkJoin {
      name = "quadlet-generated-units";
      paths = [
        (mkQuadletUnits "system" rootfulObjects)
        (mkQuadletUnits "user" rootlessObjects)
      ];
    };

    systemd.packages = [ cfg.generatedUnits ];

    systemd.services = lib.mkMerge [
      (lib.listToAttrs (map mkServiceOverride rootfulObjects))
      {
        quadlet-auto-update = lib.mkIf (cfg.autoUpdate.enable && lib.length rootfulObjects > 0) (
          mkAutoUpdate null
        );
      }
    ];

    systemd.user.services = lib.mkMerge [
      (lib.listToAttrs (map mkServiceOverride rootlessObjects))
      {
        quadlet-auto-update = lib.mkIf (cfg.autoUpdate.enable && lib.length rootlessObjects > 0) (
          mkAutoUpdate rootlessUsers
        );
        # solves `Unable to locate executable 'sh': No such file or directory`
        podman-user-wait-network-online = lib.mkIf (lib.length rootlessObjects > 0) {
          overrideStrategy = "asDropin";
          serviceConfig.ExecSearchPath = [ "/bin" ];
        };
      }
    ];
  };
}
