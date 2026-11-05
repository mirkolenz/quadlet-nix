{ config, lib, ... }:
let
  cfg = config.virtualisation.quadlet;
in
{
  imports = [
    (lib.modules.importApply ./system.nix {
      unitModule = ../units/nixos.nix;
      userManagers = true;
    })
  ];

  config = {
    virtualisation.quadlet.podman = lib.mkDefault config.virtualisation.podman.package;
    virtualisation.podman.enable = lib.mkIf (cfg.enable && cfg.allObjects != [ ]) true;
  };
}
