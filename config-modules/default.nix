{ config, ... }:
{
  flake = {
    nixosModules = {
      default = config.flake.nixosModules.quadlet;
      quadlet = import ./nixos.nix;
    };
    homeManagerModules = {
      default = config.flake.homeManagerModules.quadlet;
      quadlet = import ./hm.nix;
    };
  };
}
