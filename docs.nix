{ config, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      # Evaluate a NixOS configuration
      eval = import "${pkgs.path}/nixos/lib/eval-config.nix" {
        system = null;
        modules = [
          config.flake.nixosModules.quadlet
          (
            { lib, ... }:
            {
              documentation.nixos.options.warningsAreErrors = false;
              system.stateVersion = lib.trivial.release;
              nixpkgs = {
                inherit system pkgs;
              };
            }
          )
        ];
        prefix = [
          "virtualisation"
          "quadlet"
        ];
      };
      docs = pkgs.nixosOptionsDoc {
        inherit (eval) options;
      };
    in
    {
      packages.docs = docs.optionsCommonMark;
    };
}
