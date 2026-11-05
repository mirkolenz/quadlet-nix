{ ... }:
{
  flake = {
    nixosModules = {
      default = ./nixos.nix;
      quadlet = ./nixos.nix;
    };
    systemManagerModules = {
      default = ./system-manager.nix;
      quadlet = ./system-manager.nix;
    };
    homeModules = {
      default = ./hm.nix;
      quadlet = ./hm.nix;
    };
  };
}
