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
        ../units/common.nix
        ../units/nixos.nix
      ];
      _module.args = {
        inherit lib' podman;
        inherit (pkgs) writeShellApplication;
      };
    };

  rootfulObjects = lib.filter (obj: obj.uid == null) cfg.allObjects;
  rootlessObjects = lib.filter (obj: obj.uid != null) cfg.allObjects;

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

  # Objects only share a generator run when they share a podman storage and a
  # systemd manager, so references between units cannot cross that boundary.
  objectsByScope = lib.groupBy (
    obj: if obj.uid == null then "system" else "user-${toString obj.uid}"
  ) cfg.allObjects;

  unitPackages = lib.mapAttrsToList (
    scope: objects:
    lib'.mkQuadletUnitPackage {
      inherit pkgs podman objects;
      quadlet = cfg.package;
      type = if scope == "system" then "system" else "user";
      name = "quadlet-package-${scope}";
    }
  ) objectsByScope;

  rootfulOverrides = lib.listToAttrs (map mkServiceOverride rootfulObjects);
  rootlessOverrides = lib.listToAttrs (map mkServiceOverride rootlessObjects);

  rootfulAutoUpdate = lib.mkIf (cfg.autoUpdate.enable && rootfulObjects != [ ]) (mkAutoUpdate null);
  rootlessAutoUpdate = lib.mkIf (cfg.autoUpdate.enable && rootlessObjects != [ ]) (
    mkAutoUpdate (lib.unique (map (obj: toString obj.uid) rootlessObjects))
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
      containers = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../units/container.nix);
        default = { };
        description = "The containers to manage";
      };
      networks = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../units/network.nix);
        default = { };
        description = "The networks to manage";
      };
      pods = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../units/pod.nix);
        default = { };
        description = "The pods to manage";
      };
      kubes = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../units/kube.nix);
        default = { };
        description = "The kubes to manage";
      };
      volumes = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../units/volume.nix);
        default = { };
        description = "The volumes to manage";
      };
      builds = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../units/build.nix);
        default = { };
        description = "The builds to manage";
      };
      images = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../units/image.nix);
        default = { };
        description = "The images to manage";
      };
      artifacts = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../units/artifact.nix);
        default = { };
        description = "The artifacts to manage";
      };
    };
  };

  config = lib.mkIf (cfg.enable && cfg.allObjects != [ ]) {
    virtualisation.podman.enable = true;

    virtualisation.quadlet.podman = podman;
    virtualisation.quadlet.generatedUnits = unitPackages;

    systemd.packages = unitPackages;

    systemd.services = lib.mkMerge [
      rootfulOverrides
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
