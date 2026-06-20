{ ... }:
{
  flake = {
    nixosModules = {
      default = ./nixos.nix;
      quadlet = ./nixos.nix;
    };
    homeModules = {
      default = ./hm.nix;
      quadlet = ./hm.nix;
    };
  };
}
