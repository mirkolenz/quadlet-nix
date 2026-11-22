# Renders the rootful units of a system into files for a host without Nix,
# which needs podman 5 and systemd. Every store path the units reference
# moves below `assetDirectory`, except the `hostTools`.
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (lib.strings) storeDir;
  inherit (utils.systemdUtils.lib) socketToUnit timerToUnit;
  lib' = import ../lib.nix lib;
  quadlet = config.virtualisation.quadlet;
  cfg = quadlet.bundle;
  inherit (quadlet) podman;

  # The unit `name` at `path` with `text` as the host sees it, whose store
  # paths still point into the store, and its `relations` to targets by the
  # key of the target's drop-in, such as `Wants`.
  unitFile = name: path: text: relations: {
    inherit name path;
    text = lib.replaceStrings (lib.attrValues cfg.hostTools) (lib.attrNames cfg.hostTools) text;
    dependencies = lib.concatLists (
      lib.mapAttrsToList (
        key:
        map (target: {
          inherit key target name;
        })
      ) relations
    );
  };

  # The relations of a unit with the NixOS options of its targets.
  relations = unit: {
    Wants = unit.wantedBy;
    Requires = unit.requiredBy;
    Upholds = unit.upheldBy;
  };

  # The units of `type` by their file name, rendered by `f`.
  byFile = type: f: lib.mapAttrs' (name: unit: lib.nameValuePair "${name}.${type}" (f unit));

  # The maintenance units of `type`, whose `[Install]` the drop-ins replace.
  maintenanceUnits =
    type:
    byFile type (unit: {
      text = lib'.mkUnitText (removeAttrs unit [ "Install" ]);
      relations.Wants = unit.Install.WantedBy or [ ];
    });

  # The NixOS `units` of `type` named by `names`, as `toUnit` of NixOS
  # renders them, without its markers such as `X-Restart-Triggers` and
  # without `[Install]`, which the drop-ins replace.
  nixosUnits =
    type: toUnit: units: names:
    byFile type (unit: {
      text =
        (toUnit (
          unit
          // {
            unitConfig = lib.filterAttrs (key: _: !lib.hasPrefix "X-" key) unit.unitConfig;
            wantedBy = [ ];
          }
        )).text;
      relations = relations unit;
    }) (lib.getAttrs names units);

  maintenance = lib'.mkMaintenanceUnits quadlet podman "multi-user.target" cfg.name;

  # The units below `/etc/systemd/system` by their file name, from each source.
  systemUnitSets = [
    (lib.optionalAttrs (quadlet.allObjects != [ ]) (
      maintenanceUnits "service" maintenance.services // maintenanceUnits "timer" maintenance.timers
    ))
    (nixosUnits "socket" socketToUnit config.systemd.sockets cfg.sockets)
    (nixosUnits "timer" timerToUnit config.systemd.timers cfg.timers)
  ];
  systemUnits = lib.mergeAttrsList systemUnitSets;

  # The unit names that several sources define, such as a container named
  # like a maintenance unit.
  duplicateUnits = lib'.duplicates lib.id (
    map (obj: "${obj.serviceName}.service") quadlet.allObjects
    ++ lib.concatMap lib.attrNames systemUnitSets
  );

  unitFiles =
    map (
      obj:
      unitFile "${obj.serviceName}.service" "etc/containers/systemd/${obj.ref}" obj.text (relations obj)
    ) quadlet.allObjects
    ++ lib.mapAttrsToList (
      file: unit: unitFile file "etc/systemd/system/${file}" unit.text unit.relations
    ) systemUnits;

  dependencies = lib.concatMap (unit: unit.dependencies) unitFiles;

  # A drop-in of every target instead of `systemctl enable`, so retiring a
  # unit only removes files.
  dropins = lib.mapAttrsToList (target: deps: {
    path = "etc/systemd/system/${target}.d/${cfg.name}.conf";
    text = lib'.mkUnitText {
      Unit = lib.mapAttrs (_: lib.catAttrs "name") (lib.groupBy (dep: dep.key) deps);
    };
  }) (lib.groupBy (dep: dep.target) dependencies);

  # The text of `file` on the host, with its store paths moved below
  # `assetDirectory`.
  hostText = file: lib.replaceStrings [ "${storeDir}/" ] [ "${cfg.assetDirectory}/" ] file.text;

  # The texts of the sockets by the service they activate, which keeps the
  # old listeners of a restarted socket, so the hash of a service covers them.
  socketTexts = lib.mapAttrs (_: lib.concatMapStrings (name: systemUnits."${name}.socket".text)) (
    lib.groupBy (
      name: config.systemd.sockets.${name}.socketConfig.Service or "${name}.service"
    ) cfg.sockets
  );
  appliedHash = unit: lib.hashString "sha256" (hostText unit + socketTexts.${unit.name} or "");

  # Every file the bundle installs below `/etc`, by its path there.
  etcFiles = lib.genAttrs' (unitFiles ++ dropins) (
    file: lib.nameValuePair file.path (pkgs.writeText (lib.baseNameOf file.path) (hostText file))
  );

  # The store paths that the files reference, as Nix finds them, which the
  # bundle copies below `assetDirectory`, and every store path they depend on.
  references = pkgs.writeText "${cfg.name}-references" (
    lib.concatMapStrings (file: file.text) (unitFiles ++ dropins)
  );
  assets = pkgs.writeDirectReferencesToFile references;
  closure = pkgs.writeClosure [ references ];

  # Relative to the root of the host, like every path the bundle records.
  assetDirectoryArg = lib.escapeShellArg (lib.removePrefix "/" cfg.assetDirectory);
  # The assets by their path on the host, which the bundle copies from the
  # store path of the same name.
  assetManifest = pkgs.runCommand "assets" { } ''
    while read -r asset; do
      echo ${assetDirectoryArg}/"''${asset##*/}"
    done < ${assets} > $out
  '';

  # The records of the bundle beside its assets, one line per entry. The
  # manifests list the objects it installs, by which `retire` finds those
  # that the next installation drops, and `applied` lists the units by the
  # hash of their file, by which the installation finds those to restart.
  records =
    lib.mapAttrs (name: lines: lib.toFile name (lib.concatLines lines)) {
      units = lib.catAttrs "name" unitFiles;
      files = lib.attrNames etcFiles;
      applied = map (unit: "${unit.name} ${appliedHash unit}") unitFiles;
    }
    // {
      assets = assetManifest;
    };

  # A POSIX shell script for the host, linted at build time.
  script =
    name: text:
    pkgs.writeTextFile {
      inherit name;
      text = ''
        #!/bin/sh
        set -eu
        dir=${assetDirectoryArg}

        # Enters the root `$1` of the host, `/` by default, against which the
        # recorded paths resolve. Any other root, such as a mounted image, is
        # offline, so its systemd starts the units only at boot.
        enter() {
          cd "''${1:-/}"

          if [ "$PWD" != / ]; then
            export SYSTEMD_OFFLINE=1
          fi
        }

        # Lists the lines of `$2` absent from `$1`, treating missing files as empty.
        lacking() {
          [ -e "$1" ] || set -- /dev/null "$2"
          grep -svxFf "$1" "$2"
        }

        # Retires the installed units and files that the manifests in `$1`
        # lack. A unit that never loaded does not abort.
        retire() {
          lacking "$1/units" "$dir/units" | xargs -r -d '\n' systemctl stop || true
          lacking "$1/units" "$dir/units" | xargs -r -d '\n' systemctl reset-failed || true
          lacking "$1/files" "$dir/files" | xargs -r -d '\n' rm -f
        }

      ''
      + text;
      executable = true;
      checkPhase = "${lib.getExe pkgs.shellcheck} $target";
    };

  # Restarts every running unit whose file changed since it was last
  # applied, an image unit with every container requiring it. The units of
  # the previous bundle that this one drops stop before their files and
  # assets go.
  installScript = script "install.sh" ''
    bundle=$(cd "$(dirname "$0")" && pwd)
    enter "$@"

    # Replaces the record `$1` in `$dir` with mode `$2` atomically.
    publish() {
      install -m"$2" "$bundle/$dir/$1" "$dir/$1.partial"
      mv "$dir/$1.partial" "$dir/$1"
    }

    retire "$bundle/$dir"
    lacking "$bundle/$dir/assets" "$dir/assets" | xargs -r -d '\n' rm -rf

    mkdir -p "$dir"
    publish uninstall.sh 755

    # Recorded before creating the objects, so the uninstallation and the
    # next installation find them even if this one is interrupted.
    for manifest in assets files units; do
      publish "$manifest" 644
    done

    # Exactly the recorded files, with the modes of the host instead of
    # those of the store.
    while IFS= read -r file; do
      install -Dm644 "$bundle/$file" "$file"
    done < "$bundle/$dir/files"

    # Assets are named by their content, so only new ones are copied, each
    # completely before it takes its name.
    while IFS= read -r asset; do
      if [ ! -e "$asset" ]; then
        rm -rf "$asset.partial"
        cp -r "$bundle/$asset" "$asset.partial"
        chmod -R u+w "$asset.partial"
        mv "$asset.partial" "$asset"
      fi
    done < "$bundle/$dir/assets"

    systemctl daemon-reload
    ${lib.optionalString (dependencies != [ ])
      "systemctl start --no-block ${lib.escapeShellArgs (lib.unique (lib.catAttrs "name" dependencies))}"
    }

    # Recorded only once restarted, so a repeated installation restarts the
    # units that an interrupted one missed.
    lacking "$dir/applied" "$bundle/$dir/applied" | cut -d ' ' -f 1 | xargs -r -d '\n' systemctl try-restart --no-block
    publish applied 644
  '';

  # Installed beside the assets, so it outlives the bundle it came with.
  # Since `/dev/null` holds no manifests, it retires every recorded object.
  uninstallScript = script "uninstall.sh" ''
    enter "$@"
    retire /dev/null
    rm -rf "$dir"
    systemctl daemon-reload
  '';

  # An option listing NixOS units of the bundle by name.
  unitsOption =
    example: description:
    mkOption {
      type = with types; listOf str;
      default = [ ];
      example = [ example ];
      inherit description;
    };

  listed =
    message: names: lib.optional (names != [ ]) "${message}: ${lib.concatStringsSep ", " names}.";
  rejected = message: objects: listed message (lib.catAttrs "ref" objects);
  disabled =
    type: units: names:
    listed "disabled ${type} cannot be bundled, unlike" (
      lib.filter (name: !units.${name}.enable) names
    );
  errors =
    lib.catAttrs "message" (lib.filter (a: !a.assertion) config.assertions)
    ++ rejected "only rootful units can be bundled, unlike" (
      lib.filter (obj: obj.owner != "system") quadlet.allObjects
    )
    ++ rejected "drop-ins cannot install the aliases of" (
      lib.filter (obj: obj.aliases != [ ]) quadlet.allObjects
    )
    ++ disabled "sockets" config.systemd.sockets cfg.sockets
    ++ disabled "timers" config.systemd.timers cfg.timers
    ++ listed "unit names must be unique, unlike" duplicateUnits;

  package =
    lib.throwIf (errors != [ ])
      "virtualisation.quadlet.bundle:\n${lib.concatMapStringsSep "\n" (error: "- ${error}") errors}"
      (
        pkgs.runCommand "${cfg.name}-bundle" { } ''
          install -Dm755 ${installScript} $out/install.sh
          install -Dm755 ${uninstallScript} $out/${assetDirectoryArg}/uninstall.sh
          ${lib.concatMapAttrsStringSep "\n" (
            path: source: "install -Dm644 ${source} $out/${lib.escapeShellArg path}"
          ) etcFiles}
          ${lib.concatMapAttrsStringSep "\n" (
            name: file: "install -Dm644 ${file} $out/${assetDirectoryArg}/${name}"
          ) records}
          # Dereferenced, since symlinks such as those of `linkFarm` point
          # into the store.
          while read -r asset; do
            cp -rL ${storeDir}/"''${asset##*/}" "$out/$asset"
          done < ${assetManifest}

          # Every file must be self-contained, once the copies resolved the
          # symlinks of the assets, so none may name a store path that the
          # assets depend on, the assets included.
          if grep -rlFf ${closure} $out; then
            echo "these bundle files still reference the Nix store" >&2
            exit 1
          fi
        ''
      );
in
{
  options.virtualisation.quadlet.bundle = {
    name = mkOption {
      type = types.strMatching "[A-Za-z0-9_.-]+";
      default = "quadlet";
      description = ''
        The name of the bundle, which its drop-ins and `assetDirectory` carry,
        so several bundles can share a host.
        The bundle owns these paths, so names must not collide.
      '';
    };
    assetDirectory = mkOption {
      type = types.pathWith {
        absolute = true;
        inStore = false;
      };
      default = "/usr/local/lib/${cfg.name}";
      defaultText = lib.literalExpression ''"/usr/local/lib/''${config.virtualisation.quadlet.bundle.name}"'';
      description = "The directory of the store paths that the units of the bundle reference, which the bundle owns and its uninstallation removes";
    };
    sockets = unitsOption "web" ''
      The NixOS sockets of the bundle, such as those that activate a Quadlet
      container.
      A changed socket restarts with the service it activates, which holds
      its previous listener.
    '';
    timers = unitsOption "backup" ''
      The NixOS timers of the bundle, such as those that run a Quadlet
      container with `Type=oneshot` on a schedule.
    '';
    hostTools = mkOption {
      type = with types; attrsOf str;
      example = lib.literalExpression ''{ "/usr/bin/curl" = lib.getExe pkgs.curl; }'';
      description = ''
        The executables of the host, by their path there, that replace the
        store executables the units reference instead of being bundled.
        `systemctl` and `podman` map to `/usr/bin` by default.
      '';
    };
    package = mkOption {
      type = types.package;
      readOnly = true;
      default = package;
      defaultText = lib.literalMD "the bundle of this system's rootful units";
      description = ''
        The rootful Quadlet units of this system with the units of
        `autoUpdate` and `autoPrune`, named after `name`, the `sockets` and
        the `timers` as files for a host without Nix, with podman 5 and
        systemd, below the root they belong to.
        Its `install.sh` copies them into place, starts them, restarts those it
        changed and retires those the previous bundle had but this one lacks,
        and the `uninstall.sh` it installs into `assetDirectory` removes them.
        Both take the root of an offline host, such as a mounted image, as
        an optional argument.
      '';
    };
  };

  config.virtualisation.quadlet.bundle.hostTools = lib.mapAttrs (_: lib.mkDefault) {
    "/usr/bin/systemctl" = lib.getExe' config.systemd.package "systemctl";
    "/usr/bin/podman" = lib.getExe podman;
  };
}
