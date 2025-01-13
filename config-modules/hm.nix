{ inputs, ... }:
{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  inherit (lib) types;
  nixosUtils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" { inherit lib config pkgs; };
  systemdUtils = nixosUtils.systemdUtils;

  cfg = config.virtualisation.quadlet;
  podman = osConfig.virtualisation.podman.package or pkgs.podman;
  lib' = inputs.self.lib {
    inherit lib systemdUtils;
  };

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
      # podman rootless requires "newuidmap" (the suid version, not the non-suid one from pkgs.shadow)
      Service.ExecSearchPath = [ "/run/wrappers/bin" ];
      # Inject X-RestartIfChanged=${hash} for NixOS to detect changes.
      Unit.X-QuadletNixHash = builtins.hashString "sha256" obj.text;
      Install = { inherit (obj.installConfig) WantedBy; };
    };
in
{
  imports = [ ./common.nix ];
  options = {
    virtualisation.quadlet = {
      containers = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/container.nix);
        default = { };
      };
      networks = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/network.nix);
        default = { };
      };
      pods = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/pod.nix);
        default = { };
      };
      kubes = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/kube.nix);
        default = { };
      };
      volumes = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/volume.nix);
        default = { };
      };
      builds = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/build.nix);
        default = { };
      };
      images = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/image.nix);
        default = { };
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
        # TODO: convert to home manager service definition
        # quadlet-auto-update = lib.mkIf cfg.autoUpdate.enable (
        #   import ./update.nix {
        #     inherit lib podman;
        #     inherit (cfg.autoUpdate) startAt;
        #     autoStartTarget = "default.target";
        #     conditionUsers = [ ];
        #   }
        # );
      }
    ];
  };
}
