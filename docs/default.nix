{ lib, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    let
      mkOptions = pkgs.callPackage ./options.nix { };
      optionPackages = [
        {
          name = "nixos-options";
          title = "NixOS Options";
          value = mkOptions ../config-modules/nixos.nix;
        }
        {
          name = "home-manager-options";
          title = "Home Manager Options";
          value = mkOptions ../config-modules/hm.nix;
        }
      ];
    in
    {
      packages = {
        book = pkgs.callPackage ./book.nix { inherit optionPackages; };
        docs = config.packages.book;
      } // (lib.listToAttrs optionPackages);
    };
}
