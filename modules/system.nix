# The units of a system with NixOS-style `systemd` options, shared by NixOS
# and system-manager. `unitModule` adapts every unit to its systemd managers,
# and with `userManagers`, rootless units run in those of their owners.
{ unitModule, userManagers }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.virtualisation.quadlet;
  lib' = import ../lib.nix lib;

  # Objects only share a generator run when they share a podman storage and a
  # systemd manager, so references between units cannot cross that boundary.
  objectsByOwner = lib.groupBy (obj: obj.owner) cfg.allObjects;
  rootlessObjectsByOwner = removeAttrs objectsByOwner [ "system" ];

  # Maps the sections of a unit, such as `Service`, onto `serviceConfig`.
  toNixosUnit = lib.mapAttrs' (section: lib.nameValuePair "${lib.toLower section}Config");

  # The units of `objects` in one manager whose units start with `target`,
  # with the `[Unit]` keys `timerUnit` on every timer.
  managerUnits =
    objects: target: timerUnit:
    let
      units = lib'.mkMaintenanceUnits cfg cfg.podman target;
    in
    lib.mkIf (objects != [ ]) {
      services =
        lib.genAttrs' objects (
          obj:
          lib.nameValuePair obj.serviceName {
            overrideStrategy = "asDropin";
            inherit (obj)
              aliases
              wantedBy
              requiredBy
              upheldBy
              ;
          }
        )
        // lib.mapAttrs (_: toNixosUnit) units.services;
      timers = lib.mapAttrs (
        _: timer:
        toNixosUnit (lib.recursiveUpdate timer { Unit = timerUnit; })
        // {
          wantedBy = [ "timers.target" ];
        }
      ) units.timers;
    };

  unitPackages = lib.mapAttrsToList (
    owner: objects:
    lib'.mkQuadletUnitPackage {
      inherit pkgs objects;
      inherit (cfg) podman;
      quadlet = cfg.package;
      type = if owner == "system" then "system" else "user";
      name = "quadlet-package-${owner}";
    }
  ) objectsByOwner;
in
{
  imports = [
    (lib.modules.importApply ./common.nix unitModule)
    ./bundle.nix
  ];

  config = lib.mkIf (cfg.enable && cfg.allObjects != [ ]) {
    virtualisation.quadlet.generatedUnits = unitPackages;

    environment = lib.mkIf cfg.quadletctl.enable {
      systemPackages = [ cfg.quadletctl.package ];
      etc."xdg/quadletctl/units.tsv".text = cfg.quadletctl.units;
    };

    systemd = lib.mkMerge (
      [
        { packages = unitPackages; }
        (managerUnits (objectsByOwner.system or [ ]) "multi-user.target" { })
      ]
      # Repeated triggering conditions implement OR semantics across users.
      ++ lib.optional userManagers {
        user = managerUnits (lib.concatLists (lib.attrValues rootlessObjectsByOwner)) "default.target" {
          ConditionUser = map (user: "|${user}") (lib.attrNames rootlessObjectsByOwner);
        };
      }
    );
  };
}
