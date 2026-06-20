lib: rec {
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/systemd-lib.nix
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/systemd-unit-options.nix

  mkValueString = lib.generators.mkValueStringDefault { };
  mkKeyValue = lib.generators.mkKeyValueDefault { inherit mkValueString; } "=";

  # Quote the whole "K=V" payload (systemd C-style) so Environment=, ...
  # round-trip values with whitespace or special characters.
  # Mirrors nixpkgs/nixos/lib/systemd-lib.nix Environment= rendering.
  mkQuotedEntry = k: v: lib.strings.toJSON "${k}=${mkValueString v}";

  entryType = lib.mkOptionType {
    name = "systemd option";
    merge =
      loc: defs:
      let
        defs' = lib.filterOverrides defs;
      in
      if lib.any (def: lib.isList def.value || lib.isAttrs def.value) defs' then
        lib.concatMap (
          def:
          if lib.isAttrs def.value then lib.mapAttrsToList mkQuotedEntry def.value else lib.toList def.value
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

  quadletDocsUrl = "https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html";

  # A freeform section whose description links to the matching upstream Quadlet
  # documentation, so users discover the available keys upstream instead of in
  # declarations we would have to maintain. `anchor` is the id of the section's
  # heading in those docs.
  mkQuadletSectionOption =
    {
      description,
      anchor,
    }:
    mkSectionOption {
      description = "${lib.removeSuffix "\n" description}\n\nSee the [upstream documentation](${quadletDocsUrl}#${anchor}) for all available keys.";
    };

  mkUnitOption =
    attrs:
    lib.mkOption (
      attrs
      // {
        type = unitType;
        default = { };
      }
    );

  # Build-time guard for the unit derivations: the podman generator logs and
  # skips any unit it cannot convert rather than failing, so assert every
  # expected service file was emitted in `outDir` and fail the build otherwise
  # (all or nothing).
  mkValidateUnitsScript =
    {
      outDir,
      objects,
    }:
    let
      services = map (obj: "${obj.serviceName}.service") objects;
    in
    ''
      for service in ${lib.escapeShellArgs services}; do
        if [ ! -e "${outDir}/$service" ]; then
          echo "quadlet: the podman generator did not emit $service; aborting to avoid installing a half-generated set of units" >&2
          exit 1
        fi
      done
    '';
}
