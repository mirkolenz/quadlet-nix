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
            podman = pkgs.podman;
            type = "system";
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
