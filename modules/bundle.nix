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
  lib' = import ../lib.nix lib;
  quadlet = config.virtualisation.quadlet;
  cfg = quadlet.bundle;
  inherit (quadlet) podman;

  # The unit `name` at `path` with `text` as the host sees it, whose store
  # paths still point into the store, and its relations to the targets of
  # `unit`, each with the key of the target's drop-in.
  unitFile = name: path: text: unit: {
    inherit name path;
    text = lib.replaceStrings (lib.attrValues cfg.hostTools) (lib.attrNames cfg.hostTools) text;
    dependencies = lib.concatLists (
      lib.mapAttrsToList (option: key: map (target: { inherit key target name; }) unit.${option}) {
        wantedBy = "Wants";
        requiredBy = "Requires";
        upheldBy = "Upholds";
      }
    );
  };

  # The `[Unit]` section of the NixOS unit `unit` without the markers of
  # NixOS such as `X-Restart-Triggers`.
  unitSection = unit: lib.filterAttrs (key: _: !lib.hasPrefix "X-" key) unit.unitConfig;

  # The file of the NixOS unit `unit` named `name` as `toUnit` of NixOS
  # renders it, without `[Install]`, which the drop-ins replace.
  renderedUnitFile =
    toUnit: name: unit:
    unitFile name "etc/systemd/system/${name}"
      (toUnit (
        unit
        // {
          unitConfig = unitSection unit;
          wantedBy = [ ];
        }
      )).text
      unit;

  inherit (utils.systemdUtils.lib) socketToUnit timerToUnit;

  unitFiles =
    map (
      obj: unitFile "${obj.serviceName}.service" "etc/containers/systemd/${obj.ref}" obj.text obj
    ) quadlet.allObjects
    # Every service with its timer of the same name, if any. A service is
    # rendered here, since NixOS would add its global environment and markers.
    ++ lib.concatMap (
      name:
      let
        service = config.systemd.services.${name};
      in
      [
        (unitFile "${name}.service" "etc/systemd/system/${name}.service" (lib'.mkUnitText {
          Unit = unitSection service;
          Service = service.serviceConfig;
        }) service)
      ]
      ++ lib.optional (config.systemd.timers ? ${name}) (
        renderedUnitFile timerToUnit "${name}.timer" config.systemd.timers.${name}
      )
    ) cfg.services
    ++ lib.mapAttrsToList (name: renderedUnitFile socketToUnit "${name}.socket") (
      lib.getAttrs cfg.sockets config.systemd.sockets
    );

  dependencies = lib.concatMap (unit: unit.dependencies) unitFiles;

  # A drop-in of every target instead of `systemctl enable`, so retiring a
  # unit only removes files.
  dropins = lib.mapAttrsToList (target: deps: {
    path = "etc/systemd/system/${target}.d/${cfg.name}.conf";
    text = lib'.mkUnitText {
      Unit = lib.mapAttrs (_: lib.catAttrs "name") (lib.groupBy (dep: dep.key) deps);
    };
  }) (lib.groupBy (dep: dep.target) dependencies);

  # The files of the `tmpfiles` settings, as NixOS renders them.
  tmpfiles = lib.concatMap (
    name:
    let
      package = lib.findFirst (
        package: package.name == "${name}.conf"
      ) null config.systemd.tmpfiles.packages;
    in
    lib.optional (package != null) {
      inherit package;
      path = "etc/tmpfiles.d/${name}.conf";
      source = "${package}/lib/tmpfiles.d/${name}.conf";
    }
  ) cfg.tmpfiles;

  # The text of `file` on the host, with its store paths moved below
  # `assetDirectory`.
  hostText = file: lib.replaceStrings [ "${storeDir}/" ] [ "${cfg.assetDirectory}/" ] file.text;

  # Every file the bundle installs below `/etc`, by its path there.
  etcFiles =
    lib.genAttrs' (unitFiles ++ dropins) (
      file: lib.nameValuePair file.path (pkgs.writeText (lib.baseNameOf file.path) (hostText file))
    )
    // lib.genAttrs' tmpfiles (tmpfile: lib.nameValuePair tmpfile.path tmpfile.source);

  # The store paths that the files reference, as Nix finds them, which the
  # bundle copies below `assetDirectory`, and every store path they and the
  # tmpfiles rules depend on.
  references = pkgs.writeText "${cfg.name}-references" (
    lib.concatMapStrings (file: file.text) (unitFiles ++ dropins)
  );
  assets = pkgs.writeDirectReferencesToFile references;
  closure = pkgs.writeClosure ([ references ] ++ lib.catAttrs "package" tmpfiles);

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
      dirs = lib.unique (map (dropin: dirOf dropin.path) dropins);
      applied = map (unit: "${unit.name} ${lib.hashString "sha256" (hostText unit)}") unitFiles;
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

        # Retires the installed units, files and drop-in directories that the
        # manifests in `$1` lack. A unit that never loaded or a drop-in
        # directory that is shared or gone does not abort.
        retire() {
          lacking "$1/units" "$dir/units" | xargs -r -d '\n' systemctl stop || true
          lacking "$1/units" "$dir/units" | xargs -r -d '\n' systemctl reset-failed || true
          lacking "$1/files" "$dir/files" | xargs -r -d '\n' rm -f
          lacking "$1/dirs" "$dir/dirs" | xargs -r -d '\n' rmdir --ignore-fail-on-non-empty 2>/dev/null || true
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

    # Refuses to take over what another installation owns, so the
    # uninstallation cannot remove it.
    if [ -n "$(ls -A "$dir" 2>/dev/null)" ] && [ ! -e "$dir/files" ]; then
      echo "/$dir belongs to another installation" >&2
      exit 1
    fi

    conflicts=$(lacking "$dir/files" "$bundle/$dir/files" | while IFS= read -r file; do
      if [ -e "$file" ] || [ -L "$file" ]; then
        echo "/$file"
      fi
    done)

    if [ -n "$conflicts" ]; then
      printf 'these files belong to another installation:\n%s\n' "$conflicts" >&2
      exit 1
    fi

    retire "$bundle/$dir"
    lacking "$bundle/$dir/assets" "$dir/assets" | xargs -r -d '\n' rm -rf

    mkdir -p "$dir"
    # Claims `$dir` for the ownership check, so an interrupted first
    # installation can be repeated.
    touch "$dir/files"
    publish uninstall.sh 755

    # Recorded before creating the objects, so the uninstallation and the
    # next installation find them even if this one is interrupted.
    for manifest in assets dirs files units; do
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
    ${lib.optionalString (tmpfiles != [ ]) ''
      # By name, which an offline root resolves below itself.
      systemd-tmpfiles ''${SYSTEMD_OFFLINE:+"--root=$PWD"} --create ${
        lib.escapeShellArgs (map (tmpfile: tmpfile.package.name) tmpfiles)
      }
    ''}
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

  failed = assertions: lib.catAttrs "message" (lib.filter (a: !a.assertion) assertions);
  listed =
    message: names: lib.optional (names != [ ]) "${message}: ${lib.concatStringsSep ", " names}.";
  rejected = message: objects: listed message (lib.catAttrs "ref" objects);
  errors =
    failed config.assertions
    ++ failed cfg.assertions
    ++ rejected "only rootful units can be bundled, unlike" (
      lib.filter (obj: obj.owner != "system") quadlet.allObjects
    )
    ++ listed "disabled units cannot be bundled, unlike" (
      map (name: "${name}.service") (
        lib.filter (name: !config.systemd.services.${name}.enable) cfg.services
      )
      ++ map (name: "${name}.socket") (
        lib.filter (name: !config.systemd.sockets.${name}.enable) cfg.sockets
      )
    )
    ++ rejected "drop-ins cannot install the aliases of" (
      lib.filter (obj: obj.aliases != [ ]) quadlet.allObjects
    )
    # The environment holds the store `PATH` of NixOS beside the variables.
    ++ listed "the environment of a bundled service belongs in `serviceConfig.Environment`, unlike in" (
      lib.filter (
        name: removeAttrs config.systemd.services.${name}.environment [ "PATH" ] != { }
      ) cfg.services
    );

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
          # assets or the tmpfiles rules depend on, the assets included.
          if grep -rlFf ${closure} $out; then
            echo "these bundle files still reference the Nix store" >&2
            exit 1
          fi
        ''
      );
in
{
  options.virtualisation.quadlet.bundle = {
    services = mkOption {
      type = with types; listOf str;
      default = [ ];
      example = [ "web-reload" ];
      description = ''
        The NixOS services of the bundle beside its Quadlet units, each with
        its timer of the same name, such as the one of `startAt`.
        The bundle renders their `unitConfig`, into which NixOS folds options
        such as `requires` and `after`, and their `serviceConfig`, so they run
        executables by their absolute path.
        It rejects `environment` and scripts such as `script`, which run a
        shell from the store.
      '';
    };
    sockets = mkOption {
      type = with types; listOf str;
      default = [ ];
      example = [ "web" ];
      description = ''
        The NixOS sockets of the bundle, such as those that activate a Quadlet
        container whose service lists them in `Sockets=`.
        Make that service `PartOf=` its sockets, so a socket the installation
        restarts also restarts the service holding its old listener.
      '';
    };
    name = mkOption {
      type = types.strMatching "[A-Za-z0-9_.-]+";
      default = "quadlet";
      description = "The name of the bundle, which its drop-ins and `assetDirectory` carry, so several bundles can share a host";
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
    hostTools = mkOption {
      type = with types; attrsOf str;
      example = lib.literalExpression ''{ "/usr/bin/curl" = lib.getExe pkgs.curl; }'';
      description = ''
        The executables of the host, by their path there, that replace the
        store executables the units reference instead of being bundled.
        `systemctl` and `podman` map to `/usr/bin` by default.
      '';
    };
    tmpfiles = mkOption {
      type = with types; listOf str;
      default = [ ];
      example = [ "10-web" ];
      description = ''
        The names of the `systemd.tmpfiles.settings` that the bundle installs
        and creates, whose rules must not reference the store.
      '';
    };
    assertions = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            assertion = mkOption {
              type = types.bool;
              description = "Whether the bundle can be built";
            };
            message = mkOption {
              type = types.str;
              description = "The error if it cannot";
            };
          };
        }
      );
      default = [ ];
      description = "The assertions that only a bundle needs to hold, like the NixOS `assertions`";
    };
    package = mkOption {
      type = types.package;
      readOnly = true;
      default = package;
      defaultText = lib.literalMD "the bundle of this system's rootful units";
      description = ''
        The rootful Quadlet units, the `services` with their timers, the
        `sockets` and the `tmpfiles` of this system as files for a host without
        Nix, with podman 5 and systemd, below the root they belong to.
        Its `install.sh` copies them into place, starts them, restarts those it
        changed and retires those the previous bundle had but this one lacks,
        and the `uninstall.sh` it installs into `assetDirectory` removes them.
        Both take the root of an offline host, such as a mounted image, as
        an optional argument.
        It refuses to replace files or an `assetDirectory` that it did not
        install.
        Empty target drop-in directories are removed, even if they predate
        installation, while non-empty directories are preserved.
      '';
    };
  };

  config.virtualisation.quadlet.bundle = {
    hostTools = lib.mapAttrs (_: lib.mkDefault) {
      "/usr/bin/systemctl" = lib.getExe' config.systemd.package "systemctl";
      "/usr/bin/podman" = lib.getExe podman;
    };
    # The units of `autoUpdate` and `autoPrune`, which NixOS only defines with
    # rootful units.
    services = lib.mkIf (lib.any (obj: obj.owner == "system") quadlet.allObjects) (
      lib.attrNames (lib'.mkMaintenanceUnits quadlet podman "multi-user.target").services
    );
  };
}
