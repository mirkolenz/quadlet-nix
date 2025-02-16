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
      # Inject X-RestartIfChanged=${hash} for NixOS to detect changes.
      Unit.X-QuadletNixHash = builtins.hashString "sha256" obj.text;
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
    home.activation.quadletNix = lib.mkIf (lib.length cfg.allObjects > 0) (
      lib.hm.dag.entryBefore [ "reloadSystemd" ] ''
        mkdir -p '${config.xdg.configHome}/quadlet-nix/'
        ln -snf "''${XDG_RUNTIME_DIR:-/run/user/$UID}/systemd/generator/" '${config.xdg.configHome}/quadlet-nix/generator'
      ''
    );

    xdg.configFile = lib.mkMerge [
      (lib.mergeAttrsList (
        map (obj: {
          "containers/systemd/${obj.ref}" = {
            inherit (obj) text;
          };
          "systemd/user/${obj.serviceName}.service.d/override.conf" = {
            source = "${config.xdg.configHome}/quadlet-nix/generator/${obj.serviceName}.service";
          };
        }) cfg.allObjects
      ))
      {
        # solves `Unable to locate executable 'sh': No such file or directory`
        "systemd/user/podman-user-wait-network-online.service.d/override.conf" = {
          text = lib'.mkUnitText {
            Service.ExecSearchPath = [ "/bin" ];
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
