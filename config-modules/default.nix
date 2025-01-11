args@{ config, ... }:
{
  flake = {
    nixosModules = {
      default = config.flake.nixosModules.quadlet;
      quadlet = import ./nixos.nix args;
    };
  };
}
