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

  # Drop keys that are unset (`null`), so that typed options default to "absent"
  # and only render once given a value, and skip sections without any content.
  mkSectionText =
    name: attrs:
    let
      attrs' = lib.filterAttrs (_: v: v != null) attrs;
    in
    lib.optionalString (attrs' != { }) ''
      [${name}]
      ${mkSectionConfig attrs'}
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

  # A freeform submodule that exposes every known Quadlet key of a section as an
  # explicitly typed option while still passing through any unknown key via the
  # freeform `sectionType`. Known keys default to `null` so they are only rendered
  # into the unit file once set (see `mkSectionText`). `anchor` is the id of the
  # section's heading in the upstream documentation; it is woven into the section
  # description and into every key's description (each links there instead of
  # copying upstream prose that quickly goes stale). `mkKeyOption` turns a key spec
  # (see `mkQuadletOption`) into a typed option now that the name and url are known.
  mkQuadletSectionOption =
    {
      description,
      anchor,
      options,
    }:
    let
      url = "${quadletDocsUrl}#${anchor}";
      mkKeyOption =
        name:
        {
          type,
          flag,
          default,
          example,
        }:
        lib.mkOption (
          {
            type = lib.types.nullOr type;
            default = null;
            description = lib.concatStringsSep "\n\n" (
              lib.optional (flag != null) "Equivalent to the Podman `${flag}` option."
              ++ [ "See [`${name}=`](${url}) in the upstream Quadlet documentation." ]
            );
          }
          // lib.optionalAttrs (default != null) {
            defaultText = lib.literalExpression (lib.generators.toPretty { } default);
          }
          // lib.optionalAttrs (example != null) {
            example = lib.literalExpression (lib.generators.toPretty { } example);
          }
        );
    in
    lib.mkOption {
      description = "${lib.removeSuffix "\n" description}\n\nSee the [upstream documentation](${url}) for all available keys.";
      default = { };
      type = lib.types.submodule {
        freeformType = sectionType;
        options = lib.mapAttrs mkKeyOption options;
      };
    };

  # A value that may be given as a single element or as a list of elements, used
  # for Quadlet keys that may be repeated. A single element is coerced into a
  # one-element list so that repeated definitions (e.g. spread across several
  # modules) accumulate instead of conflicting, matching the verbatim passthrough
  # of the freeform `sectionType`. The list type also documents the repeatability.
  singleOrList = elemType: lib.types.coercedTo elemType lib.singleton (lib.types.listOf elemType);

  # A key holding `key=value` entries, given as an attribute set (recommended,
  # quoted automatically), a single string, or a list of strings. The string and
  # list forms accumulate across definitions via `singleOrList`.
  keyValue =
    let
      scalar = lib.types.either lib.types.str lib.types.int;
    in
    lib.types.oneOf [
      (lib.types.attrsOf scalar)
      (singleOrList lib.types.str)
    ];

  # Declare a typed Quadlet key. Returns a spec that `mkQuadletSectionOption`
  # finalizes into an option once it knows the key's name and section anchor.
  # The conveniences mirror `lib.mkOption`:
  #   - `type` is wrapped in `nullOr` and the key defaults to `null` (absent), so
  #     it is only rendered once explicitly set. A declared type is stricter than
  #     the freeform `sectionType` fallback and cannot be overridden inline, so keep
  #     it permissive and avoid `enum`, which would reject values added upstream,
  #   - `flag` records the equivalent Podman CLI flag and is folded into the
  #     generated description, which links to the upstream docs instead of copying
  #     prose that quickly goes stale,
  #   - `example` takes any value and is pretty-printed as a Nix expression; for
  #     repeatable keys pass a list to document the list form,
  #   - `default` documents Podman's own default via `defaultText` only; the actual
  #     option default stays `null` so the key is never written unless explicitly set.
  mkQuadletOption =
    {
      type,
      flag ? null,
      default ? null,
      example ? null,
    }:
    assert lib.assertMsg (example == null || default == null || example != default)
      "mkQuadletOption: `example` (${
        lib.generators.toPretty { } example
      }) is redundant with `default`; drop it or pick a different example";
    assert lib.assertMsg ((type.name or null) != "bool" || example == null)
      "mkQuadletOption: boolean options must not set `example` (the type already implies `true`/`false`); document the `default` instead";
    {
      inherit
        type
        flag
        default
        example
        ;
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
}
