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
  nixImageLoad = lib'.mkNixImageLoad pkgs;

  mkSubmodule =
    path:
    types.submodule {
      imports = [
        path
        ../units/common.nix
        ../units/nixos.nix
      ];
      _module.args = {
        inherit lib' podman nixImageLoad;
        inherit (cfg) images;
      };
    };

  # Objects only share a generator run when they share a podman storage and a
  # systemd manager, so references between units cannot cross that boundary.
  objectsByOwner = lib.groupBy (obj: obj.owner) cfg.allObjects;
  rootfulObjects = objectsByOwner.system or [ ];
  rootlessObjectsByOwner = removeAttrs objectsByOwner [ "system" ];
  rootlessObjects = lib.concatLists (lib.attrValues rootlessObjectsByOwner);

  # Maps the sections of a unit, such as `Service`, onto `serviceConfig`, ...
  toNixosUnit = lib.mapAttrs' (section: lib.nameValuePair "${lib.toLower section}Config");

  # The units of the `objects` in one manager, whose timers in user managers
  # only fire for the owners of rootless objects.
  mkManagerUnits =
    objects: users: target:
    let
      units = lib'.mkMaintenanceUnits cfg podman target;
    in
    lib.mkIf (objects != [ ]) {
      services =
        lib.genAttrs' objects mkServiceOverride
        // lib.mapAttrs (_: toNixosUnit) units.services
        // lib.mapAttrs (
          _: dropin: toNixosUnit dropin // { overrideStrategy = "asDropin"; }
        ) units.serviceDropins;
      # Repeated triggering conditions implement OR semantics across users.
      timers = lib.mapAttrs (
        _: timer:
        toNixosUnit (lib.recursiveUpdate timer { Unit.ConditionUser = map (user: "|${user}") users; })
        // {
          wantedBy = [ "timers.target" ];
        }
      ) units.timers;
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

    environment = lib.mkIf cfg.quadletctl.enable {
      systemPackages = [ cfg.quadletctl.package ];
      etc."xdg/quadletctl/units.tsv".text = cfg.quadletctl.units;
    };

    systemd = lib.mkMerge [
      { packages = unitPackages; }
      (mkManagerUnits rootfulObjects [ ] "multi-user.target")
      { user = mkManagerUnits rootlessObjects (lib.attrNames rootlessObjectsByOwner) "default.target"; }
    ];
  };
}
