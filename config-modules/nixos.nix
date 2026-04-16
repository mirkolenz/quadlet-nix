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
      nameSuffix ? type,
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

  systemctl = lib.getExe' pkgs.systemd "systemctl";
  loginctl = lib.getExe' pkgs.systemd "loginctl";
  userBus = uid: "--machine=${uid}@.host --user";
  userStateGuard = uid: ''
    state=$(${loginctl} show-user ${uid} --property=State --value 2>/dev/null || true)
    case "$state" in
      active|online|lingering) ;;
      *)
        echo "quadlet-user-reload: user ${uid} not ready (state=''${state:-unknown}); skipping" >&2
        exit 0
        ;;
    esac
  '';

  mkUserSweeper =
    uid: _objects:
    lib.nameValuePair "quadlet-user-reload-${uid}" {
      description = "Sweep rootless quadlet state for user ${uid}";
      wantedBy = [ "multi-user.target" ];
      after = [ "user@${uid}.service" ];
      restartTriggers = [ rootlessUnitsByUid.${uid} ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${userStateGuard uid}
        ${systemctl} ${userBus uid} daemon-reload
        stale=()
        while read -r unit _; do stale+=("$unit"); done < <(
          ${systemctl} ${userBus uid} list-units --type=service --state=not-found --no-legend --plain
        )
        if (( ''${#stale[@]} > 0 )); then
          ${systemctl} ${userBus uid} stop "''${stale[@]}" || \
            echo "quadlet-user-reload: failed to stop one or more stale units" >&2
          ${systemctl} ${userBus uid} reset-failed "''${stale[@]}" || true
        fi
      '';
    };

  mkUserUnitReloader =
    obj:
    let
      uid = toString obj.uid;
      service = "${obj.serviceName}.service";
    in
    lib.nameValuePair "quadlet-user-reload-${uid}-${obj.serviceName}" {
      description = "Reload rootless quadlet unit ${service} for user ${uid}";
      wantedBy = [ "multi-user.target" ];
      after = [
        "user@${uid}.service"
        "quadlet-user-reload-${uid}.service"
      ];
      restartTriggers = [
        obj.text
        podman
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${userStateGuard uid}
        active=$(${systemctl} ${userBus uid} show --property=ActiveState --value ${service} 2>/dev/null || true)
        case "$active" in
          activating|deactivating)
            echo "quadlet-user-reload: skipping ${service} (state=$active)" >&2
            exit 0
            ;;
        esac
        ${systemctl} ${userBus uid} reset-failed ${service} || true
        ${systemctl} ${userBus uid} reload-or-restart ${service} || \
          echo "quadlet-user-reload: reload-or-restart ${service} failed" >&2
      '';
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

  config = lib.mkIf (cfg.enable && lib.length cfg.allObjects > 0) {
    virtualisation.podman.enable = true;

    virtualisation.quadlet.generatedUnits = pkgs.symlinkJoin {
      name = "quadlet-generated-units";
      paths = [ rootfulUnits ] ++ lib.attrValues rootlessUnitsByUid;
    };

    systemd.packages = [ cfg.generatedUnits ];

    systemd.services = lib.mkMerge [
      (lib.listToAttrs (map mkServiceOverride rootfulObjects))
      (lib.mkIf cfg.reloadUserServices (
        lib.mkMerge [
          (lib.mapAttrs' mkUserSweeper rootlessObjectsByUid)
          (lib.listToAttrs (map mkUserUnitReloader (lib.filter (obj: obj.autoStart) rootlessObjects)))
        ]
      ))
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
          mkAutoUpdate (lib.attrNames rootlessObjectsByUid)
        );
        podman-user-wait-network-online = lib.mkIf (lib.length rootlessObjects > 0) {
          overrideStrategy = "asDropin";
          serviceConfig.ExecSearchPath = [
            "/bin"
            "${lib.getBin pkgs.coreutils}/bin"
          ];
        };
      }
    ];
  };
}
