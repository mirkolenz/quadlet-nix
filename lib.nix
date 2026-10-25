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

  # Podman stores a Nix-built image in a namespace of its own, tagged with a
  # hash of its store path, so that a fixed tag such as `latest` cannot hide a
  # new build. The hash carries no string context, since only the load step
  # needs the image built.
  nixImageReference =
    image: "localhost/quadlet-nix/${image.imageName}:${lib.hashString "sha256" image.outPath}";

  # The `ExecStartPre=` running the load script for the Nix-built `image`.
  mkNixImageLoad =
    pkgs:
    let
      script = lib.getExe (pkgs.callPackage ./pkgs/nix-image-load/package.nix { });
    in
    image:
    lib.escapeShellArgs [
      script
      (nixImageReference image)
      "${image}"
    ];

  # The units of the `autoUpdate` and `autoPrune` options in a manager whose
  # units start with `target`, without the install of the timers.
  mkMaintenanceUnits = cfg: podman: target: {
    services = lib.optionalAttrs cfg.autoPrune.enable {
      # Runs after `target`, so that a missed run does not remove the images
      # of units that are about to start.
      quadlet-image-prune = {
        Unit = {
          Description = "Prune unused Podman images";
          After = [ target ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${lib.getExe podman} image prune --all --force";
        };
      };
    };
    # Podman ships the service, which would otherwise never time out on a hanging pull.
    serviceDropins = lib.optionalAttrs cfg.autoUpdate.enable {
      podman-auto-update.Service.TimeoutStartSec = 900;
    };
    timers =
      lib.optionalAttrs cfg.autoUpdate.enable {
        quadlet-auto-update = {
          Unit.Description = "Update the Podman images of Quadlet units";
          Timer = {
            OnCalendar = cfg.autoUpdate.startAt;
            Persistent = true;
            RandomizedDelaySec = 900;
            Unit = "podman-auto-update.service";
          };
        };
      }
      // lib.optionalAttrs cfg.autoPrune.enable {
        quadlet-image-prune = {
          Unit.Description = "Prune unused Podman images";
          Timer = {
            OnCalendar = cfg.autoPrune.startAt;
            Persistent = true;
          };
        };
      };
  };

  mkNixImageOption =
    description:
    lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      example = lib.literalExpression "pkgs.dockerTools.streamLayeredImage { name = \"web\"; }";
      description = ''
        ${description}, either an archive (e.g., `pkgs.dockerTools.buildLayeredImage`) or a stream (e.g., `pkgs.dockerTools.streamLayeredImage`).
        It is only loaded unless this build is already present.
      '';
    };

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

  # Build time guard. The podman generator logs and skips invalid units, so
  # assert every expected service file was emitted before installing the package.
  mkQuadletUnitPackage =
    {
      pkgs,
      podman,
      quadlet,
      type,
      objects,
      name,
    }:
    let
      outDir = "$out/lib/systemd/${type}";
      services = map (obj: "${obj.serviceName}.service") objects;
      # The generator emits the source directory as `SourcePath=`, so one
      # directory per object keeps a change to one object out of the units of
      # all others. A single generator run still resolves references between
      # units such as `Pod=` or `Network=`.
      unitDirs = map (obj: pkgs.writeTextDir obj.ref obj.text) objects;
    in
    pkgs.runCommand name
      {
        QUADLET_UNIT_DIRS = lib.concatStringsSep ":" unitDirs;
        PODMAN = lib.getExe podman;
      }
      ''
        mkdir -p "${outDir}"
        ${lib.getExe quadlet} ${lib.optionalString (type == "user") "-user"} "${outDir}"

        for service in ${lib.escapeShellArgs services}; do
          if [ ! -e "${outDir}/$service" ]; then
            echo "quadlet: the podman generator did not emit $service, aborting to avoid installing a partially generated set of units" >&2
            exit 1
          fi
        done
      '';
}
