{
  lib,
  pkgs,
}:
rec {
  nixosUtils = import "${pkgs.path}/nixos/lib/utils.nix" {
    inherit lib pkgs;
    config = { };
  };
  inherit (nixosUtils) systemdUtils;
  inherit (systemdUtils.unitOptions) unitOption;

  mkSectionConfig =
    attrs:
    lib.mapAttrs (
      _: value: if lib.isAttrs value then lib.mapAttrsToList (n: v: "${n}=${toString v}") value else value
    ) attrs;

  mkSectionText =
    name: attrs:
    lib.optionalString (attrs != { }) ''
      [${name}]
      ${systemdUtils.lib.attrsToSection (mkSectionConfig attrs)}
    '';

  mkUnitText = unitConfig: lib.concatLines (lib.mapAttrsToList mkSectionText unitConfig);

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
