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
      # Inject X-RestartIfChanged=${hash} for NixOS to detect changes.
      unitConfig.X-QuadletNixHash = builtins.hashString "sha256" obj.text;
      inherit (obj)
        aliases
        wantedBy
        requiredBy
        upheldBy
        ;
    };

  mkQuadletName =
    obj:
    if obj.uid == null then "containers/systemd/${obj.ref}" else "containers/systemd/users/${obj.ref}";

  mkSystemdName =
    obj:
    if obj.uid == null then
      "etc/systemd/system/${obj.serviceName}.service"
    else
      "etc/systemd/user/${obj.serviceName}.service";

  mkSystemdPath =
    obj:
    if obj.uid == null then
      "/run/systemd/generator/${obj.serviceName}.service"
    else
      "/run/user/${toString obj.uid}/systemd/generator/${obj.serviceName}.service";
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
    virtualisation.podman.enable = true;

    environment.etc = lib.listToAttrs (
      map (
        obj:
        lib.nameValuePair (mkQuadletName obj) {
          inherit (obj) text;
        }
      ) cfg.allObjects
    );
    # The symlinks are not necessary for the services to be honored by systemd,
    # but necessary for NixOS activation process to pick them up for updates.
    systemd.packages = lib.singleton (
      pkgs.linkFarm "quadlet-nix" (
        map (obj: {
          name = mkSystemdName obj;
          path = mkSystemdPath obj;
        }) cfg.allObjects
      )
    );
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
