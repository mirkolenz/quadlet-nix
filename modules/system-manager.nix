# Rootful units only, since system-manager has no user managers. Podman reads
# its configuration in `/etc/containers` from the host or from the
# `containers` module of NixOS.
{ config, lib, ... }:
let
  cfg = config.virtualisation.quadlet;
  lib' = import ../lib.nix lib;
in
{
  imports = [
    (lib.modules.importApply ./system.nix {
      unitModule = {
        owner = "system";
        autoStartTarget = "multi-user.target";
      };
      userManagers = false;
    })
  ];

  config = lib.mkIf (cfg.enable && cfg.allObjects != [ ]) {
    assertions = [
      (lib'.mkUnsupportedAssertion "system-manager" [ "aliases" "upheldBy" ] cfg.allObjects)
    ];

    # Unlike NixOS, system-manager restarts a unit only when its drop-in
    # changes, not the generated unit beside it. A unit that references a
    # changed one restarts with it, through the `Requires=` or `BindsTo=`
    # that the generator adds.
    systemd.services = lib.genAttrs' cfg.allObjects (
      obj:
      lib.nameValuePair obj.serviceName {
        restartTriggers = [
          obj.text
          cfg.podman
          cfg.package
        ];
      }
    );
  };
}
