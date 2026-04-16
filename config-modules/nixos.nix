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
  rootlessObjectsByUid = lib.groupBy (obj: toString obj.uid) rootlessObjects;

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
    {
      type,
      nameSuffix,
      objects,
    }:
    pkgs.runCommand "quadlet-package-${nameSuffix}"
      {
        QUADLET_UNIT_DIRS = pkgs.symlinkJoin {
          name = "quadlet-directory-${nameSuffix}";
          paths = map (obj: pkgs.writeTextDir obj.ref obj.text) objects;
        };
      }
      ''
        mkdir -p $out/lib/systemd/${type}/
        ${podman}/lib/systemd/${type}-generators/podman-${type}-generator $out/lib/systemd/${type}/
      '';

  rootfulUnits = mkQuadletUnits {
    type = "system";
    nameSuffix = "system";
    objects = rootfulObjects;
  };

  rootlessUnitsByUid = lib.mapAttrs (
    uid: objects:
    mkQuadletUnits {
      type = "user";
      nameSuffix = "user-${uid}";
      inherit objects;
    }
  ) rootlessObjectsByUid;

  mkUserReloader =
    uid:
    lib.nameValuePair "quadlet-user-reload-${uid}" {
      description = "Restart user manager for uid ${uid} to apply quadlet changes";
      wantedBy = [ "multi-user.target" ];
      after = [ "user@${uid}.service" ];
      restartTriggers = [ rootlessUnitsByUid.${uid} ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        ${lib.getExe' pkgs.systemd "systemctl"} try-restart "user@${uid}.service"
      '';
    };

  rootfulOverrides = lib.listToAttrs (map mkServiceOverride rootfulObjects);
  rootlessOverrides = lib.listToAttrs (map mkServiceOverride rootlessObjects);

  userReloadServices = lib.listToAttrs (map mkUserReloader (lib.attrNames rootlessObjectsByUid));

  rootfulAutoUpdate = lib.mkIf (cfg.autoUpdate.enable && rootfulObjects != [ ]) (mkAutoUpdate null);
  rootlessAutoUpdate = lib.mkIf (cfg.autoUpdate.enable && rootlessObjects != [ ]) (
    mkAutoUpdate (lib.attrNames rootlessObjectsByUid)
  );

  podmanWaitOverride = lib.mkIf (rootlessObjects != [ ]) {
    overrideStrategy = "asDropin";
    serviceConfig.ExecSearchPath = [
      "/bin"
      "${lib.getBin pkgs.coreutils}/bin"
      "${lib.getBin pkgs.systemd}/bin"
    ];
  };
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
      reloadUserServices = lib.mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to emit a per-UID reloader service that restarts the
          `user@UID.service` manager whenever any rootless quadlet unit
          file changes, mimicking a logout/login. The user manager then
          comes back up with the new unit files and reactivates its
          autostart units.

          Without this, `nixos-rebuild switch` updates unit files on disk
          but the running `systemd --user` instance keeps the old containers
          going until manually restarted.
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
      artifacts = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/artifact.nix);
        default = { };
        description = "The artifacts to manage";
      };
    };
  };

  config = lib.mkIf (cfg.enable && cfg.allObjects != [ ]) {
    virtualisation.podman.enable = true;

    virtualisation.quadlet.generatedUnits = pkgs.symlinkJoin {
      name = "quadlet-generated-units";
      paths = [ rootfulUnits ] ++ lib.attrValues rootlessUnitsByUid;
    };

    systemd.packages = [ cfg.generatedUnits ];

    systemd.services = lib.mkMerge [
      rootfulOverrides
      (lib.mkIf cfg.reloadUserServices userReloadServices)
      { quadlet-auto-update = rootfulAutoUpdate; }
    ];

    systemd.user.services = lib.mkMerge [
      rootlessOverrides
      {
        quadlet-auto-update = rootlessAutoUpdate;
        podman-user-wait-network-online = podmanWaitOverride;
      }
    ];
  };
}
