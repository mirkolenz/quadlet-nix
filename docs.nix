{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Evaluate a NixOS configuration
      eval = import "${pkgs.path}/nixos/lib/eval-config.nix" {
        system = null;
        baseModules = [ ];
        modules = [
          self.nixosModules.default
          (
            { lib, ... }:
            {
              options = {
                # add stubs for upstream modules
                assertions = lib.mkOption { internal = true; };
                environment = lib.mkOption { internal = true; };
                virtualisation.podman = lib.mkOption { internal = true; };
                systemd = lib.mkOption { internal = true; };
                _module.args = lib.mkOption { internal = true; };
              };
              config = {
                _module.args = {
                  inherit pkgs;
                };
              };
            }
          )
        ];
      };
      docs = pkgs.nixosOptionsDoc {
        inherit (eval) options;
      };
    in
    {
      packages.docs = pkgs.runCommand "docs" { } ''
        mkdir -p $out
        substitute ${docs.optionsCommonMark} $out/docs.md \
          --replace-fail "file://${self.outPath}" "https://github.com/mirkolenz/quadlet-nix/blob/main" \
          --replace-fail "${self.outPath}" "quadlet-nix"
      '';
    };
}
