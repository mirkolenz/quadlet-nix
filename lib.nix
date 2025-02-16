lib: rec {
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/systemd-lib.nix
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/systemd-unit-options.nix

  mkValueString = lib.generators.mkValueStringDefault { };
  mkKeyValue = lib.generators.mkKeyValueDefault { inherit mkValueString; } "=";

  entryType = lib.mkOptionType {
    name = "systemd option";
    merge =
      loc: defs:
      let
        defs' = lib.filterOverrides defs;
      in
      if lib.any (def: lib.isList def.value || lib.isAttrs def.value) defs' then
        lib.concatMap (
          def: if lib.isAttrs def.value then lib.mapAttrsToList mkKeyValue def.value else lib.toList def.value
        ) defs'
      else
        lib.mergeEqualOption loc defs';
  };
  sectionType = lib.types.attrsOf entryType;
  unitType = lib.types.attrsOf sectionType;

  mkEntryConfig = n: v: map (v': mkKeyValue n v') (lib.toList v);

  mkSectionConfig = attrs: lib.concatLines (lib.concatLists (lib.mapAttrsToList mkEntryConfig attrs));

  mkSectionText =
    name: attrs:
    lib.optionalString (attrs != { }) ''
      [${name}]
      ${mkSectionConfig attrs}
    '';

  mkUnitText = unitConfig: lib.concatLines (lib.mapAttrsToList mkSectionText unitConfig);

  mkSectionOption =
    attrs:
    lib.mkOption (
      attrs
      // {
        type = sectionType;
        default = { };
      }
    );

  mkUnitOption =
    attrs:
    lib.mkOption (
      attrs
      // {
        type = unitType;
        default = { };
      }
    );
}
