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
    lib.nixosSystem {
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
      inherit (self.legacyPackages.${system}) mkBundle;
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
      # Whether the bundle of `quadlet` fails evaluation.
      rejectsBundle =
        quadlet:
        !(lib.tryEval (mkBundle { modules = [ { virtualisation.quadlet = quadlet; } ]; }).drvPath).success;

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
              # and the `[Install]` section only reach the generator as text.
              containers.raw = {
                uid = 1000;
                rawConfig = ''
                  [Container]
                  Image=localhost/raw:latest
                  Pod=group.pod

                  [Install]
                  Alias=raw-alias.service
                  RequiredBy=default.target
                  UpheldBy=default.target
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

            # The generator emits the symlinks of an `[Install]` section next to the unit.
            for link in raw-alias.service default.target.requires/raw.service default.target.upholds/raw.service; do
              [[ -e "$after/$link" ]]
            done

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
          && lib.hasInfix "ConditionUser=1000" uidScopeUnits.rootless.text
          && !lib.hasInfix "ConditionUser" uidScopeUnits.rootful.text
        );
        # The image unit loads the Nix-built image under its own tag, which the
        # pull then finds. A oneshot keeps systemd's restart defaults.
        nix-image = mkBoolCheck "quadlet-nix-image" (
          lib.all (lib.flip lib.hasInfix nixImage.images.web.text) [
            "Image=localhost/quadlet/web:"
            "Policy=missing"
            "quadlet-load"
          ]
          && lib.hasPrefix "localhost/quadlet/web:" nixImage.images.web.podmanName
          # A container loads its image package itself, with the same script,
          # into the storage that its global arguments select.
          && lib.all (lib.flip lib.hasInfix nixImage.containers.direct.text) [
            "Image=localhost/quadlet/direct:"
            "quadlet-load"
            " --module=/etc/module.conf --root=/srv/storage"
          ]
          # No registry provides a Nix-built image to auto-update from.
          && lib.all (unit: lib.hasInfix "AutoUpdate=disabled" unit.text) [
            nixImage.containers.direct
            nixImage.containers.web
          ]
          && lib.hasInfix "Restart=on-failure" nixImage.containers.web.text
          && lib.all (unit: !lib.hasInfix "Restart=" unit.text && !unit.autoStart) [
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
          && lib.hasInfix "Image=localhost/quadlet/web:" deprecated.virtualisation.quadlet.containers.web.text
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
