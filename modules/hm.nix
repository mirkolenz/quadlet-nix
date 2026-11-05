{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  cfg = config.virtualisation.quadlet;
  inherit (cfg) podman;
  lib' = import ../lib.nix lib;
  units = lib'.mkMaintenanceUnits cfg podman "default.target";

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
    map mkEntry ([ service ] ++ depPaths);
in
{
  imports = [ (lib.modules.importApply ./common.nix { owner = "user"; }) ];

  config = lib.mkMerge [
    { virtualisation.quadlet.podman = lib.mkDefault config.services.podman.package; }
    (lib.mkIf (cfg.enable && cfg.allObjects != [ ]) {
      services.podman = {
        enable = true;
        package = lib.mkDefault (osConfig.virtualisation.podman.package or pkgs.podman);
        # Opt-in like ours, which would otherwise run beside it.
        autoUpdate.enable = lib.mkDefault false;
      };

      virtualisation.quadlet.generatedUnits = lib.singleton unitPackage;

      # A linked file outside the unit directory is a distinct unit to systemd,
      # and the store paths of home-manager allow no relative alias symlink.
      assertions = [ (lib'.mkUnsupportedAssertion "home-manager" [ "aliases" ] cfg.allObjects) ];

      xdg.configFile =
        lib.listToAttrs (lib.concatMap mkObjectConfigEntries cfg.allObjects)
        // lib.optionalAttrs cfg.quadletctl.enable {
          "quadletctl/units.tsv".text = cfg.quadletctl.units;
        };

      home.packages = lib.mkIf cfg.quadletctl.enable [ cfg.quadletctl.package ];

      systemd.user = {
        inherit (units) services;
        timers = lib.mapAttrs (_: timer: timer // { Install.WantedBy = [ "timers.target" ]; }) units.timers;
      };
    })
  ];
}
