{
  lib,
  systemdUtils,
}:
rec {
  inherit (systemdUtils.unitOptions) unitOption;

  mkUnitText =
    config:
    lib.concatLines (
      lib.mapAttrsToList (name: value: ''
        [${name}]
        ${systemdUtils.lib.attrsToSection value}
      '') config
    );

  mkUnitOption =
    attrs:
    lib.mkOption (
      attrs
      // {
        type = lib.types.attrsOf unitOption;
        default = { };
      }
    );
}
