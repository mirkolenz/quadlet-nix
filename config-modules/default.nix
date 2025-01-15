{ ... }:
{
  flake = {
    nixosModules = {
      default = ./nixos.nix;
      quadlet = ./nixos.nix;
    };
    homeManagerModules = {
      default = ./hm.nix;
      quadlet = ./hm.nix;
    };
  };
}
