{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) types;

  cfg = config.virtualisation.quadlet;
  podman = config.virtualisation.podman.package;
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

  # Objects only share a generator run when they share a podman storage and a
  # systemd manager, so references between units cannot cross that boundary.
  objectsByOwner = lib.groupBy (obj: obj.owner) cfg.allObjects;
  rootfulObjects = objectsByOwner.system or [ ];
  rootlessObjectsByOwner = removeAttrs objectsByOwner [ "system" ];
  rootlessObjects = lib.concatLists (lib.attrValues rootlessObjectsByOwner);

  # Enables the auto-update timer that Podman ships, scheduled at `startAt`
  # and, in user managers, limited to the owners of rootless objects.
  autoUpdateTimer =
    objects: users:
    lib.mkIf (cfg.autoUpdate.enable && objects != [ ]) {
      wantedBy = [ "timers.target" ];
      overrideStrategy = "asDropin";
      timerConfig.OnCalendar = [
        ""
        cfg.autoUpdate.startAt
      ];
      # Repeated triggering conditions implement OR semantics across users.
      unitConfig.ConditionUser = map (user: "|${user}") users;
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

  unitPackages = lib.mapAttrsToList (
    owner: objects:
    lib'.mkQuadletUnitPackage {
      inherit pkgs podman objects;
      quadlet = cfg.package;
      type = if owner == "system" then "system" else "user";
      name = "quadlet-package-${owner}";
    }
  ) objectsByOwner;

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

    environment = lib.mkIf cfg.quadletctl.enable {
      systemPackages = [ cfg.quadletctl.package ];
      etc."xdg/quadletctl/units.tsv".text = cfg.quadletctl.units;
    };

    systemd.services = lib.genAttrs' rootfulObjects mkServiceOverride;
    systemd.user.services = lib.genAttrs' rootlessObjects mkServiceOverride;

    systemd.timers.podman-auto-update = autoUpdateTimer rootfulObjects [ ];
    systemd.user.timers.podman-auto-update = autoUpdateTimer rootlessObjects (
      lib.attrNames rootlessObjectsByOwner
    );
  };
}
