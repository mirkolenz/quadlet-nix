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
      Unit = lib.mapAttrs (_: map (dep: dep.name)) (lib.groupBy (dep: dep.key) deps);
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

  # Every file the bundle installs below `/etc`, by its path there, with its
  # store paths moved below `assetDirectory`.
  etcFiles =
    lib.genAttrs' (unitFiles ++ dropins) (
      file:
      lib.nameValuePair file.path (
        pkgs.writeText (lib.baseNameOf file.path) (
          lib.replaceStrings [ "${storeDir}/" ] [ "${cfg.assetDirectory}/" ] file.text
        )
      )
    )
    // lib.genAttrs' tmpfiles (tmpfile: lib.nameValuePair tmpfile.path tmpfile.source);

  # The store paths that the files reference, as Nix finds them, which the
  # bundle copies below `assetDirectory`, and every store path they and the
  # tmpfiles rules depend on.
  references = pkgs.writeText "${cfg.name}-references" (
    lib.concatMapStrings (file: file.text) (unitFiles ++ dropins)
  );
  assets = pkgs.writeDirectReferencesToFile references;
  closure = pkgs.writeClosure ([ references ] ++ map (tmpfile: tmpfile.package) tmpfiles);

  assetDirectoryArg = lib.escapeShellArg cfg.assetDirectory;

  # The units and files of the installed bundle, by which the next one finds
  # those it drops.
  manifests = lib.mapAttrs (name: lines: lib.toFile name (lib.concatLines lines)) {
    units = map (unit: unit.name) unitFiles;
    files = map (path: "/${path}") (lib.attrNames etcFiles);
  };
  assetPath = name: lib.escapeShellArg "${cfg.assetDirectory}/${name}";
  # Stops the installed units and removes the installed files that the
  # manifests `keptUnits` and `keptFiles` lack. A unit that never loaded,
  # such as one the generator rejected, does not abort.
  retire = keptUnits: keptFiles: ''
    grep -svxFf ${keptUnits} ${assetPath "units"} | xargs -r systemctl stop || true
    grep -svxFf ${keptFiles} ${assetPath "files"} | xargs -r rm -f
  '';

  # A POSIX shell script for the host, linted at build time.
  script =
    name: text:
    pkgs.writeTextFile {
      inherit name;
      text = "#!/bin/sh\nset -eu\n" + text;
      executable = true;
      checkPhase = "${lib.getExe pkgs.shellcheck} $target";
    };

  # Restarts every running unit whose file the installation changes, an image
  # unit with every container requiring it. The units of the previous bundle
  # that this one drops stop before their files and assets go.
  installScript = script "install.sh" ''
    # Installs this bundle, starts its units and restarts those it changed,
    # collected as the positional parameters.
    cd "$(dirname "$0")"
    set --
    ${lib.concatMapStrings (bundled: ''
      cmp -s ${lib.escapeShellArg bundled.path} ${lib.escapeShellArg "/${bundled.path}"} || set -- "$@" ${lib.escapeShellArg bundled.name}
    '') unitFiles}
    ${retire ".${assetPath "units"}" ".${assetPath "files"}"}
    cp -r etc/. /etc/
    # Assets are named by their content, so only new ones are copied, and
    # those that no unit references any more are removed.
    mkdir -p ${assetDirectoryArg}
    for asset in .${assetDirectoryArg}/*; do
      if [ ! -e "''${asset#.}" ]; then
        cp -r "$asset" ${assetDirectoryArg}/
      fi
    done
    # Unlike the assets, these change without changing their name.
    cp .${assetPath "units"} .${assetPath "files"} .${assetPath "uninstall.sh"} ${assetDirectoryArg}/
    for asset in ${assetDirectoryArg}/*; do
      if [ ! -e ".$asset" ]; then
        rm -rf "$asset"
      fi
    done
    systemctl daemon-reload
    ${lib.optionalString (tmpfiles != [ ])
      "systemd-tmpfiles --create ${lib.escapeShellArgs (map (tmpfile: "/${tmpfile.path}") tmpfiles)}"
    }
    ${lib.optionalString (dependencies != [ ])
      "systemctl start --no-block ${lib.escapeShellArgs (lib.unique (map (dep: dep.name) dependencies))}"
    }

    if [ $# -gt 0 ]; then
      systemctl try-restart --no-block "$@"
    fi
  '';

  # Installed beside the assets, so it outlives the bundle it came with.
  uninstallScript = script "uninstall.sh" ''
    # Stops and removes the installed bundle, but keeps the directories its
    # tmpfiles rules created.
    ${retire "/dev/null" "/dev/null"}
    rm -rf ${assetDirectoryArg}
    systemctl daemon-reload
  '';

  failed = assertions: map (a: a.message) (lib.filter (a: !a.assertion) assertions);
  listed =
    message: names: lib.optional (names != [ ]) "${message}: ${lib.concatStringsSep ", " names}.";
  rejected = message: objects: listed message (map (obj: obj.ref) objects);
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
          # Without any files, `install.sh` still finds an empty `etc`.
          mkdir -p $out/etc
          install -Dm755 ${installScript} $out/install.sh
          install -Dm755 ${uninstallScript} $out${assetPath "uninstall.sh"}
          ${lib.concatMapAttrsStringSep "\n" (
            path: source: "install -Dm644 ${source} $out/${lib.escapeShellArg path}"
          ) etcFiles}
          ${lib.concatMapAttrsStringSep "\n" (
            name: source: "install -Dm644 ${source} $out${assetPath name}"
          ) manifests}
          # Dereferenced, since symlinks such as those of `linkFarm` point
          # into the store.
          while read -r asset; do
            cp -rL "$asset" $out${assetDirectoryArg}/
          done < ${assets}

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
      description = "The directory of the store paths that the units of the bundle reference";
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
