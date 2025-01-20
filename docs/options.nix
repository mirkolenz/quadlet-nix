{
  lib,
  pkgs,
  nixosOptionsDoc,
}:
let
  eval = lib.evalModules {
    modules = [
      ../config-modules/nixos.nix
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
  docs = nixosOptionsDoc {
    inherit (eval) options;
    # hide /nix/store/* prefix
    transformOptions = opt: opt // { declarations = [ ]; };
  };
in
docs.optionsCommonMark
