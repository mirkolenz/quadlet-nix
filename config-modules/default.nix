args@{ config, ... }:
{
  flake = {
    nixosModules = {
      default = config.flake.nixosModules.quadlet;
      quadlet = import ./nixos.nix args;
    };
    homeManagerModules = {
      default = config.flake.homeManagerModules.quadlet;
      quadlet = import ./hm.nix args;
    };
  };
}
