{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  inherit (lib) types;

  cfg = config.virtualisation.quadlet;
  podman = osConfig.virtualisation.podman.package or pkgs.podman;
  lib' = import ../lib.nix lib;

  mkSubmodule =
    path:
    types.submodule {
      imports = [
        path
        ../quadlet-modules/common.nix
      ];
      _module.args = {
        inherit lib' podman;
        inherit (pkgs) writeShellApplication;
      };
    };

  mkServiceOverride =
    obj:
    lib.nameValuePair obj.serviceName {
      Install = {
        Alias = obj.aliases;
        WantedBy = obj.wantedBy;
        RequiredBy = obj.requiredBy;
        UpheldBy = obj.upheldBy;
      };
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
    };
  };

  config = lib.mkIf (cfg.enable && lib.length cfg.allObjects > 0) {
    virtualisation.quadlet.generatedUnits =
      pkgs.runCommand "quadlet-generated-units"
        {
          QUADLET_UNIT_DIRS = pkgs.symlinkJoin {
            name = "quadlet-directory";
            paths = map (obj: pkgs.writeTextDir obj.ref obj.text) cfg.allObjects;
          };
        }
        ''
          mkdir -p $out/lib/systemd/user/
          ${lib.getLib podman}/lib/systemd/user-generators/podman-user-generator $out/lib/systemd/user/
        '';

    xdg.configFile = lib.mkMerge [
      (lib.mapAttrs' (
        _: obj:
        lib.nameValuePair "systemd/user/${obj.serviceName}.service" {
          source = "${config.virtualisation.quadlet.generatedUnits}/lib/systemd/user/${obj.serviceName}.service";
        }
      ) cfg.allObjects)
      {
        "systemd/user/podman-user-wait-network-online.service.d/override.conf" = {
          text = lib'.mkUnitText {
            Service.ExecSearchPath = [
              "/bin"
              "${lib.getBin pkgs.coreutils}/bin"
            ];
            Install.WantedBy = [ "default.target" ];
          };
        };
      }
    ];

    systemd.user.services = lib.mkMerge [
      (lib.listToAttrs (map mkServiceOverride cfg.allObjects))
      {
        quadlet-auto-update =
          let
            defs = import ./update.nix {
              inherit lib podman;
              inherit (cfg.autoUpdate) startAt;
            };
          in
          lib.mkIf cfg.autoUpdate.enable {
            Service = defs.serviceConfig // {
              ExecStart = defs.script;
            };
            Unit = defs.unitConfig // {
              Description = defs.description;
            };
            Install = {
              Wants = defs.wants;
              After = defs.after;
            };
          };
      }
    ];

    systemd.user.timers.quadlet-auto-update = lib.mkIf cfg.autoUpdate.enable {
      Unit = {
        Description = "Quadlet auto-update timer";
      };
      Timer = {
        OnCalendar = cfg.autoUpdate.startAt;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
