{
  lib,
  self,
  inputs,
  ...
}:
let
  quadletModule = {
    imports = [ self.nixosModules.quadlet ];
    virtualisation.quadlet.enable = true;
  };
  commonTestConfig =
    { pkgs, ... }:
    {
      imports = [ quadletModule ];
      environment.systemPackages = with pkgs; [ curl ];
      virtualisation.podman.enable = true;
      # The owner of the rootless containers.
      users.users.quadlet = {
        isSystemUser = true;
        uid = 990;
        linger = true;
        home = "/var/lib/quadlet";
        createHome = true;
        shell = pkgs.shadow;
        autoSubUidGidRange = true;
        group = "quadlet";
      };
      users.groups.quadlet.gid = 990;
      virtualisation = {
        graphics = false;
        cores = 4;
        memorySize = 4096;
      };
    };
in
{
  # basic checks to see if the module can be evaluated
  flake.nixosConfigurations = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
    system:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = lib.singleton (
        { modulesPath, lib, ... }:
        {
          imports = [
            quadletModule
            "${modulesPath}/virtualisation/qemu-vm.nix"
          ];
          system.stateVersion = lib.trivial.release;
        }
      );
    }
  );
  # advanced checks using virtual machines
  perSystem =
    { pkgs, system, ... }:
    let
      # The nixpkgs flake is the only channel-specific input, so a check can be
      # repeated against another channel by passing a different one.
      evalQuadlet =
        nixpkgs: quadlet:
        (nixpkgs.lib.nixosSystem {
          modules = [
            {
              imports = [ quadletModule ];
              nixpkgs.pkgs = nixpkgs.legacyPackages.${system};
              system.stateVersion = nixpkgs.lib.trivial.release;
              virtualisation.quadlet = quadlet;
            }
          ];
        }).config;

      # Assert the generated unit package refuses to build, aborting activation.
      # `serviceName` is derived from the name, so raw text that renames or
      # breaks the emitted unit must trip the guard.
      mkAbortCheck =
        name: text:
        let
          units =
            lib.head
              (evalQuadlet inputs.nixpkgs { containers.app.rawConfig = text; })
              .virtualisation.quadlet.generatedUnits;
        in
        pkgs.runCommand name { failed = pkgs.testers.testBuildFailure units; } ''
          [[ 1 = $(cat $failed/testBuildFailure.exit) ]]
          touch $out
        '';

      # Assert a condition decided during evaluation. A Nix bool reaches the
      # builder as "1" when true and as the empty string when false.
      mkBoolCheck =
        name: passed:
        pkgs.runCommand name { inherit passed; } ''
          [[ -n "$passed" ]]
          touch $out
        '';

      # Assert the module rejects the configuration with an assertion whose
      # message names the offending objects.
      mkAssertionCheck =
        name: quadlet: expected:
        mkBoolCheck name (
          lib.any (
            assertion: !assertion.assertion && lib.hasInfix expected assertion.message
          ) (evalQuadlet inputs.nixpkgs quadlet).assertions
        );

      # A system-manager configuration, whose toplevel fails on assertions.
      evalSystemManager =
        quadlet:
        inputs.system-manager.lib.makeSystemConfig {
          modules = lib.singleton {
            imports = [ self.systemManagerModules.quadlet ];
            nixpkgs.hostPlatform = system;
            virtualisation.quadlet = {
              enable = true;
            }
            // quadlet;
          };
        };
      systemManager = evalSystemManager {
        autoUpdate.enable = true;
        containers.web.containerConfig.Image = "localhost/web:latest";
      };

      # A rootful and a rootless container to compare the two systemd scopes.
      uidScope = evalQuadlet inputs.nixpkgs {
        containers.rootful.containerConfig.Image = "localhost/rootful:latest";
        containers.rootless = {
          uid = 1000;
          containerConfig.Image = "localhost/rootless:latest";
        };
      };
      uidScopeUnits = uidScope.virtualisation.quadlet.containers;

      # Deprecated options keep working and only warn. `autoUpdate` adds its timer.
      deprecated = evalQuadlet inputs.nixpkgs {
        autoUpdate.enable = true;
        containers.web = {
          imageStream = pkgs.dockerTools.streamLayeredImage { name = "web"; };
          installConfig.WantedBy = "default.target";
        };
      };

      # One Nix-built image loaded for two containers, one of them a oneshot
      # like the kube.
      nixImage =
        (evalQuadlet inputs.nixpkgs {
          images.web.package = pkgs.dockerTools.streamLayeredImage { name = "web"; };
          containers.web.containerConfig.Image = "web.image";
          containers.job = {
            containerConfig.Image = "web.image";
            serviceConfig.Type = "oneshot";
          };
          containers.direct = {
            imagePackage = pkgs.dockerTools.streamLayeredImage { name = "direct"; };
            containerConfig = {
              GlobalArgs = "--root=/srv/storage";
              ContainersConfModule = "/etc/module.conf";
            };
          };
          containers.renamed.containerConfig.ServiceName = "service";
          kubes.job = {
            kubeConfig.Yaml = "job.yaml";
            serviceConfig.Type = "oneshot";
          };
        }).virtualisation.quadlet;

      # A bundle of an archive image, a store volume of symlinks, a NixOS
      # service with its timer, a socket and a tmpfiles setting.
      mkBundle = args: self.lib.mkBundle ({ inherit pkgs; } // args);
      bundled = mkBundle {
        modules = lib.singleton (
          { config, ... }:
          {
            systemd.tmpfiles.settings."10-web"."/var/lib/web".d.mode = "0700";
            systemd.sockets.web = {
              wantedBy = [ "sockets.target" ];
              listenStreams = [ "8080" ];
              socketConfig.Service = "web.service";
            };
            systemd.services.web-reload = {
              after = [ "web.service" ];
              startAt = "daily";
              serviceConfig.ExecStart = "${lib.getExe' config.systemd.package "systemctl"} try-restart web.service";
            };
            virtualisation.quadlet = {
              images.web.imageConfig = {
                Image = "docker-archive:${pkgs.runCommand "web.tar.gz" { } "touch $out"}";
                ImageTag = "localhost/web:latest";
              };
              containers.web.containerConfig = {
                Image = "web.image";
                Volume = "${
                  pkgs.linkFarm "content" { "index.html" = pkgs.writeText "index.html" "hello"; }
                }:/srv:ro";
              };
              bundle = {
                name = "web";
                tmpfiles = [ "10-web" ];
                services = [ "web-reload" ];
                sockets = [ "web" ];
              };
            };
          }
        );
      };
      # The successor of `bundled` without its image, service, timer, socket
      # and tmpfiles setting.
      bundledReduced = mkBundle {
        modules = [
          {
            virtualisation.quadlet = {
              bundle.name = "web";
              containers.web.containerConfig.Image = "localhost/web:latest";
            };
          }
        ];
      };
      bundledEmpty = mkBundle {
        modules = [ { virtualisation.quadlet.bundle.name = "web"; } ];
      };
      # Whether the derivation `drv` fails evaluation.
      failsEval = drv: !(lib.tryEval drv.drvPath).success;
      rejectsBundle =
        quadlet:
        failsEval (mkBundle {
          modules = [ { virtualisation.quadlet = quadlet; } ];
        });

      mkUnits =
        nixpkgs: publishPort:
        pkgs.symlinkJoin {
          name = "quadlet-units";
          paths =
            (evalQuadlet nixpkgs {
              networks.shared.uid = 1000;
              containers.web = {
                uid = 1000;
                containerConfig = {
                  Image = "localhost/web:latest";
                  Network = "shared.network";
                  PublishPort = "${publishPort}:80";
                };
              };
              # Shares the generator run with `web` and sets several keys of
              # each flag map, so its unit is regenerated on every change to
              # `web` and only a deterministic generator keeps it identical.
              containers.sibling = {
                uid = 1000;
                containerConfig = {
                  Image = "localhost/sibling:latest";
                  Network = "shared.network";
                  AddHost = "sibling:127.0.0.1";
                  Tmpfs = "/tmp";
                  DNS = "127.0.0.53";
                  Memory = "2g";
                  Pull = "newer";
                  ShmSize = "64m";
                };
              };
              containers.other = {
                uid = 1001;
                containerConfig.Image = "localhost/other:latest";
              };
              pods.group.uid = 1000;
              # Raw text bypasses the structured options, so the pod membership
              # only reaches the generator as text.
              containers.raw = {
                uid = 1000;
                rawConfig = ''
                  [Container]
                  Image=localhost/raw:latest
                  Pod=group.pod
                '';
              };
            }).virtualisation.quadlet.generatedUnits;
        };

      mkGeneratedUnitsCheck =
        name: nixpkgs:
        pkgs.runCommand name
          {
            before = "${mkUnits nixpkgs "8080"}/lib/systemd/user";
            after = "${mkUnits nixpkgs "8081"}/lib/systemd/user";
          }
          ''
            package() { dirname "$(readlink -f "$after/$1")"; }

            # References resolve within a uid, and every uid has its own package.
            grep -q "^Requires=shared-network.service$" "$after/web.service"
            grep -q "^Wants=raw.service$" "$after/group-pod.service"
            [[ "$(package web.service)" = "$(package shared-network.service)" ]]
            [[ "$(package web.service)" != "$(package other.service)" ]]

            # Changing one object must leave every other generated unit byte-identical.
            for unit in shared-network.service sibling.service group-pod.service raw.service other.service; do
              diff "$before/$unit" "$after/$unit"
            done
            ! cmp -s "$before/web.service" "$after/web.service"

            touch $out
          '';
    in
    {
      checks = {
        # `ServiceName=` renames the emitted unit; the unsupported key makes the
        # generator reject it. Both leave the expected `app.service` missing.
        validation-partial = mkAbortCheck "quadlet-validation-partial" ''
          [Container]
          Image=localhost/test:latest
          ServiceName=renamed
        '';
        validation-invalid = mkAbortCheck "quadlet-validation-invalid" ''
          [Container]
          Image=localhost/test:latest
          ThisKeyDoesNotExist=true
        '';
        # The links of an `[Install]` section would be distinct units.
        install-links = mkAbortCheck "quadlet-install-links" ''
          [Container]
          Image=localhost/test:latest

          [Install]
          Alias=alias.service
        '';
        duplicate-refs = mkAssertionCheck "quadlet-duplicate-refs" {
          containers.a.name = "dup";
          containers.b = {
            name = "dup";
            containerConfig.ServiceName = "distinct";
          };
        } "not unique: dup.container";
        generated-units = mkGeneratedUnitsCheck "quadlet-generated-units" inputs.nixpkgs;
        generated-units-stable = mkGeneratedUnitsCheck "quadlet-generated-units-stable" inputs.nixpkgs-stable;
        # `uid` selects the systemd manager: null gives a system unit started by
        # `multi-user.target`, a positive uid a user unit guarded by `ConditionUser=`.
        uid-scope = mkBoolCheck "quadlet-uid-scope" (
          uidScope.systemd.services.rootful.wantedBy == [ "multi-user.target" ]
          && uidScope.systemd.user.services.rootless.wantedBy == [ "default.target" ]
          && uidScopeUnits.rootless.finalConfig.Unit.ConditionUser == 1000
          && !uidScopeUnits.rootful.finalConfig.Unit ? ConditionUser
        );
        # The image unit loads the Nix-built image under its own tag, which the
        # pull then finds. A oneshot keeps systemd's restart defaults.
        nix-image = mkBoolCheck "quadlet-nix-image" (
          lib.hasPrefix "localhost/quadlet/web:" nixImage.images.web.finalConfig.Image.Image
          && nixImage.images.web.finalConfig.Image.Policy == "missing"
          && lib.any (lib.hasInfix "quadlet-load") nixImage.images.web.finalConfig.Service.ExecStartPre
          && lib.hasPrefix "localhost/quadlet/web:" nixImage.images.web.podmanName
          # A container loads its image package itself, with the same script,
          # into the storage that its global arguments select.
          && lib.hasPrefix "localhost/quadlet/direct:" nixImage.containers.direct.finalConfig.Container.Image
          && lib.any (
            exec:
            lib.hasInfix "quadlet-load" exec
            && lib.hasSuffix " --module=/etc/module.conf --root=/srv/storage" exec
          ) nixImage.containers.direct.finalConfig.Service.ExecStartPre
          # No registry provides a Nix-built image to auto-update from.
          && lib.all (unit: unit.finalConfig.Container.AutoUpdate == "disabled") [
            nixImage.containers.direct
            nixImage.containers.web
          ]
          && nixImage.containers.web.finalConfig.Service.Restart == "on-failure"
          && lib.all (unit: !unit.finalConfig.Service ? Restart && !unit.autoStart) [
            nixImage.containers.job
            nixImage.kubes.job
          ]
        );
        # Quadlet names a container after its service.
        podman-names = mkBoolCheck "quadlet-podman-names" (
          nixImage.containers.renamed.podmanName == "systemd-service"
        );
        deprecated-options = mkBoolCheck "quadlet-deprecated-options" (
          deprecated.systemd.timers.quadlet-update.wantedBy == [ "timers.target" ]
          && lib.count (lib.hasInfix "deprecated") deprecated.warnings == 2
          && lib.elem "default.target" deprecated.systemd.services.web.wantedBy
          && lib.hasPrefix "localhost/quadlet/web:" deprecated.virtualisation.quadlet.containers.web.finalConfig.Container.Image
        );
        bundle = pkgs.runCommand "quadlet-bundle" { } ''
          set -euo pipefail
          cd ${bundled}
          grep -qx 'Wants=web.service' etc/systemd/system/multi-user.target.d/web.conf
          grep -qx 'Wants=web-reload.timer' etc/systemd/system/timers.target.d/web.conf
          grep -qx 'Wants=web.socket' etc/systemd/system/sockets.target.d/web.conf
          grep -qx 'ListenStream=8080' etc/systemd/system/web.socket
          grep -qx 'Service=web.service' etc/systemd/system/web.socket
          grep -qx 'ExecStart=/usr/bin/systemctl try-restart web.service' etc/systemd/system/web-reload.service
          grep -qx 'After=web.service' etc/systemd/system/web-reload.service
          grep -qx 'OnCalendar=daily' etc/systemd/system/web-reload.timer
          grep -qE '^Image=docker-archive:/usr/local/lib/web/[^/]+-web.tar.gz$' etc/containers/systemd/web.image
          test -f usr/local/lib/web/*-content/index.html
          test -f etc/tmpfiles.d/10-web.conf
          test -x install.sh -a -x usr/local/lib/web/uninstall.sh
          touch $out
        '';
        # Installs `bundled` on an offline host whose systemd only logs its calls,
        # replaces it with its successor in an installation interrupted before
        # the restarts and its repetition, and uninstalls it, which must restore
        # the host.
        bundle-lifecycle = pkgs.runCommand "quadlet-bundle-lifecycle" { } ''
          set -euo pipefail
          export STATE=$PWD PATH=$PWD/bin:$PATH
          mkdir bin
          # Fails the daemon reload once after `touch "$STATE/interrupt"`.
          cat > bin/systemctl <<'EOF'
          #!/bin/sh
          [ "$SYSTEMD_OFFLINE" = 1 ] || exit 1
          echo "''${0##*/} $*" >> "$STATE/calls"
          if [ "$1" = daemon-reload ] && rm "$STATE/interrupt" 2>/dev/null; then
            exit 1
          fi
          EOF
          cp bin/systemctl bin/systemd-tmpfiles
          # Fails the copy to `$FAIL` after writing part of it.
          cat > bin/install <<'EOF'
          #!/bin/sh
          for destination do :; done

          if [ "$destination" = "''${FAIL-}" ]; then
            printf partial > "$destination"
            exit 1
          fi

          exec ${pkgs.coreutils}/bin/install "$@"
          EOF
          chmod +x bin/*

          mkdir -p host/etc/systemd/system host/etc/containers/systemd host/etc/tmpfiles.d host/usr/local/lib
          cd host
          mkdir -m710 etc/systemd/system/multi-user.target.d
          mkdir -m750 etc/systemd/system/timers.target.d
          touch etc/systemd/system/{multi-user,timers}.target.d/foreign.conf

          install_bundle() { "$1/install.sh" .; }
          uninstall() { usr/local/lib/web/uninstall.sh .; }
          fails() { if "$@"; then exit 1; fi; }
          snapshot() { find . -printf '%p %y %m\n' | sort; }
          pristine=$(snapshot)
          restored() { [[ $(snapshot) = "$pristine" ]]; }

          # Installations that would take over files of the host fail without
          # changing it.
          mkdir usr/local/lib/web
          touch usr/local/lib/web/foreign
          fails install_bundle ${bundled}
          rm -r usr/local/lib/web
          touch etc/containers/systemd/web.container
          fails install_bundle ${bundled}
          rm etc/containers/systemd/web.container
          restored

          # Failed metadata copies must permit retrying a fresh installation
          # and uninstalling an interrupted upgrade.
          for metadata in uninstall.sh units files dirs assets applied; do
            FAIL=usr/local/lib/web/$metadata.partial fails install_bundle ${bundled}
            test -f usr/local/lib/web/files
            install_bundle ${bundled}
            uninstall
            restored

            install_bundle ${bundled}
            FAIL=usr/local/lib/web/$metadata.partial fails install_bundle ${bundledReduced}
            uninstall
            restored
          done

          mkdir etc/systemd/system/sockets.target.d
          install_bundle ${bundled}
          grep -qx 'systemctl start --no-block web.service web-reload.timer web.socket' "$STATE/calls"
          grep -qx "systemd-tmpfiles --root=$PWD --create 10-web.conf" "$STATE/calls"
          touch "$STATE/interrupt"
          fails install_bundle ${bundledReduced}
          grep -qx 'systemctl stop web-image.service web-reload.service web-reload.timer web.socket' "$STATE/calls"
          install_bundle ${bundledReduced}
          [[ $(tail -1 "$STATE/calls") = 'systemctl try-restart --no-block web.service' ]]
          [[ ! -e etc/systemd/system/sockets.target.d && ! -e etc/systemd/system/web.socket ]]
          test -f etc/containers/systemd/web.container
          [[ $(ls usr/local/lib/web) = $(ls ${bundledReduced}/usr/local/lib/web) ]]
          uninstall
          restored

          # An empty bundle retires everything without issuing bare unit commands.
          install_bundle ${bundled}
          install_bundle ${bundledEmpty}
          : > "$STATE/calls"
          uninstall
          [[ $(cat "$STATE/calls") = 'systemctl daemon-reload' ]]
          restored
          touch $out
        '';
        # The loader of a Nix-built image runs a shell from the store.
        bundle-store-reference =
          pkgs.runCommand "quadlet-bundle-store-reference"
            {
              failed = pkgs.testers.testBuildFailure (mkBundle {
                modules = [
                  { virtualisation.quadlet.images.web.package = pkgs.dockerTools.examples.nginxStream; }
                ];
              });
            }
            ''
              grep -q "still reference the Nix store" $failed/testBuildFailure.log
              touch $out
            '';
        bundle-rejects = mkBoolCheck "quadlet-bundle-rejects" (
          !rejectsBundle { containers.web.containerConfig.Image = "localhost/web:latest"; }
          && rejectsBundle {
            containers.web = {
              uid = 1000;
              containerConfig.Image = "localhost/web:latest";
            };
          }
          && rejectsBundle {
            bundle.assertions = [
              {
                assertion = false;
                message = "rejected";
              }
            ];
          }
        );
        # system-manager installs the generated unit with its drop-in, starts it
        # with its own target and rejects what it cannot install, and its units
        # can be bundled like those of NixOS.
        system-manager = pkgs.runCommand "quadlet-system-manager" { } ''
          set -euo pipefail
          cd ${systemManager.config.environment.etc."systemd/system".source}
          grep -q '^ExecStart=.*/podman run ' web.service
          test -f web.service.d/overrides.conf
          test -e system-manager.target.wants/web.service
          test -e system-manager.target.wants/quadlet-update.timer
          test -f ${systemManager.config.virtualisation.quadlet.bundle.package}/etc/containers/systemd/web.container
          grep -qF '${systemManager.config.virtualisation.quadlet.quadletctl.units}' \
            ${systemManager.config.environment.etc."xdg/quadletctl/units.tsv".source}
          touch $out
        '';
        system-manager-rejects = mkBoolCheck "quadlet-system-manager-rejects" (
          failsEval (evalSystemManager {
            containers.web = {
              aliases = [ "alias.service" ];
              containerConfig.Image = "localhost/web:latest";
            };
          })
        );
        # system-manager restarts a unit whose drop-in changed, so the drop-in
        # must change with the generated unit.
        system-manager-restarts = mkBoolCheck "quadlet-system-manager-restarts" (
          systemManager.config.systemd.units."web.service".unit != (evalSystemManager {
            containers.web.containerConfig.Image = "localhost/other:latest";
          }).config.systemd.units."web.service".unit
        );
        nixos = pkgs.testers.runNixOSTest {
          name = "nixos";
          imports = [ ./nixos.nix ];
          defaults = commonTestConfig;
        };
        hm = pkgs.testers.runNixOSTest {
          name = "hm";
          imports = [ ./hm.nix ];
          defaults = {
            imports = [
              commonTestConfig
              inputs.home-manager.nixosModules.default
            ];
            home-manager.sharedModules = [ self.homeModules.quadlet ];
          };
        };
      };
    };
}
