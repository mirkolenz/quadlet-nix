{ self, lib, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    let
      eval = lib.evalModules {
        modules = [
          self.nixosModules.default
          (
            { lib, ... }:
            {
              options._module.args = lib.mkOption { visible = false; };
              config = {
                _module.args = {
                  inherit pkgs;
                };
                _module.check = false;
              };
            }
          )
        ];
      };
      docs = pkgs.nixosOptionsDoc {
        inherit (eval) options;
        # hide /nix/store/* prefix
        transformOptions = opt: opt // { declarations = [ ]; };
      };
    in
    {
      apps.docs.program = pkgs.writeShellApplication {
        name = "docs";
        text = ''
          cp -f ${config.packages.docs} ./docs.md
        '';
      };
      packages.docs = pkgs.runCommand "docs.md" { } ''
        sed '1s/^/# quadlet-nix\n\n/' ${docs.optionsCommonMark} > $out
        ${lib.getExe pkgs.comrak} --inplace $out
      '';
    };
}
