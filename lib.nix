{
  lib,
  systemdUtils,
}:
rec {
  inherit (systemdUtils.unitOptions) unitOption;

  mkSectionText =
    name: attrs:
    lib.optionalString (attrs != { }) ''
      [${name}]
      ${systemdUtils.lib.attrsToSection attrs}
    '';

  mkUnitText = config: lib.concatLines (lib.mapAttrsToList mkSectionText config);

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
