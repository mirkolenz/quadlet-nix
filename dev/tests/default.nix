{
  lib,
  self,
  inputs,
  ...
}:
let
  commonTestConfig =
    { pkgs, ... }:
    {
      imports = [ self.nixosModules.quadlet ];
      environment.systemPackages = with pkgs; [ curl ];
      virtualisation.podman.enable = true;
      virtualisation.quadlet.enable = true;
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
            self.nixosModules.quadlet
            "${modulesPath}/virtualisation/qemu-vm.nix"
          ];
          system.stateVersion = lib.trivial.release;
          virtualisation.quadlet.enable = true;
        }
      );
    }
  );
  # advanced checks using virtual machines
  perSystem =
    { pkgs, ... }:
    let
      # Assert the generated unit package refuses to build, aborting activation.
      # `serviceName` is derived from the name, so raw text that renames or
      # breaks the emitted unit must trip the guard.
      mkAbortCheck =
        name: text:
        let
          units = self.lib.mkQuadletUnitPackage {
            inherit pkgs;
            inherit (pkgs) podman;
            type = "system";
            name = "quadlet-package-system";
            objects = lib.singleton {
              serviceName = "app";
              ref = "app.container";
              inherit text;
            };
          };
        in
        pkgs.runCommand name { failed = pkgs.testers.testBuildFailure units; } ''
          [[ 1 = $(cat $failed/testBuildFailure.exit) ]]
          touch $out
        '';

      mkUnits =
        publishPort:
        pkgs.symlinkJoin {
          name = "quadlet-units";
          paths =
            (lib.nixosSystem {
              modules = lib.singleton {
                imports = [ self.nixosModules.quadlet ];
                nixpkgs.pkgs = pkgs;
                system.stateVersion = lib.trivial.release;
                virtualisation.quadlet = {
                  enable = true;
                  networks.shared.uid = 1000;
                  containers.web = {
                    uid = 1000;
                    containerConfig = {
                      Image = "localhost/web:latest";
                      Network = "shared.network";
                      PublishPort = "${publishPort}:80";
                    };
                  };
                  containers.other = {
                    uid = 1001;
                    containerConfig.Image = "localhost/other:latest";
                  };
                };
              };
            }).config.virtualisation.quadlet.generatedUnits;
        };
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
        generated-units =
          pkgs.runCommand "quadlet-generated-units"
            {
              before = "${mkUnits "8080"}/lib/systemd/user";
              after = "${mkUnits "8081"}/lib/systemd/user";
            }
            ''
              package() { dirname "$(readlink -f "$after/$1")"; }

              # references resolve within a uid, and every uid has its own package
              grep -q "^Requires=shared-network.service$" "$after/web.service"
              [[ "$(package web.service)" = "$(package shared-network.service)" ]]
              [[ "$(package web.service)" != "$(package other.service)" ]]

              # changing one object leaves the units of all others untouched
              diff "$before/shared-network.service" "$after/shared-network.service"
              diff "$before/other.service" "$after/other.service"
              ! diff "$before/web.service" "$after/web.service" > /dev/null

              touch $out
            '';
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
