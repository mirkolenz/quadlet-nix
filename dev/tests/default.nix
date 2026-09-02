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

      # Assert the module rejects the configuration at evaluation time with a
      # message naming the offending objects.
      mkAssertionCheck =
        name: quadlet: expected:
        pkgs.runCommand name
          {
            rejected = lib.any (
              assertion: !assertion.assertion && lib.hasInfix expected assertion.message
            ) (evalQuadlet inputs.nixpkgs quadlet).assertions;
          }
          ''
            [[ -n "$rejected" ]]
            touch $out
          '';

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
