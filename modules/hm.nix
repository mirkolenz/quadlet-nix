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
  podman = config.services.podman.package;
  lib' = import ../lib.nix lib;
  units = lib'.mkMaintenanceUnits cfg podman "default.target";
  nixImageLoad = lib'.mkNixImageLoad pkgs;

  mkSubmodule =
    path:
    types.submodule {
      imports = [
        path
        ../units/common.nix
      ];
      owner = "user";
      _module.args = {
        inherit lib' podman nixImageLoad;
        inherit (cfg) images;
      };
    };

  # A home-manager configuration always covers a single user, so all objects
  # share one generator run and references between units always resolve.
  unitPackage = lib'.mkQuadletUnitPackage {
    inherit pkgs podman;
    quadlet = cfg.package;
    name = "quadlet-package-user";
    type = "user";
    objects = cfg.allObjects;
  };

  mkObjectConfigEntries =
    obj:
    let
      service = "${obj.serviceName}.service";
      source = "${unitPackage}/lib/systemd/user/${service}";
      mkEntry = path: lib.nameValuePair "systemd/user/${path}" { inherit source; };
      depsByDir = {
        wants = obj.wantedBy;
        requires = obj.requiredBy;
        upholds = obj.upheldBy;
      };
      depPaths = lib.concatLists (
        lib.mapAttrsToList (dir: map (target: "${target}.${dir}/${service}")) depsByDir
      );
    in
    map mkEntry ([ service ] ++ obj.aliases ++ depPaths);
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
    services.podman = {
      enable = true;
      package = lib.mkDefault (osConfig.virtualisation.podman.package or pkgs.podman);
      # Opt-in like ours, with which it conflicts.
      autoUpdate.enable = lib.mkDefault false;
    };

    assertions = lib.singleton {
      assertion = !(cfg.autoUpdate.enable && config.services.podman.autoUpdate.enable);
      message = "`virtualisation.quadlet.autoUpdate.enable` and `services.podman.autoUpdate.enable` both define `podman-auto-update.service`, enable only one of them.";
    };

    virtualisation.quadlet.podman = podman;
    virtualisation.quadlet.generatedUnits = lib.singleton unitPackage;

    xdg.configFile =
      lib.listToAttrs (lib.concatMap mkObjectConfigEntries cfg.allObjects)
      # The services that Podman ships are not in the unit search path
      # unless Podman is installed system-wide.
      // lib.concatMapAttrs (name: dropin: {
        "systemd/user/${name}.service".source = "${podman}/lib/systemd/user/${name}.service";
        "systemd/user/${name}.service.d/quadlet.conf".text = lib'.mkUnitText dropin;
      }) units.serviceDropins
      // lib.optionalAttrs cfg.quadletctl.enable {
        "quadletctl/units.tsv".text = cfg.quadletctl.units;
      };

    home.packages = lib.mkIf cfg.quadletctl.enable [ cfg.quadletctl.package ];

    systemd.user = {
      inherit (units) services;
      timers = lib.mapAttrs (_: timer: timer // { Install.WantedBy = [ "timers.target" ]; }) units.timers;
    };
  };
}
