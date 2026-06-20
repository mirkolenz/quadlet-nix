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
    {
      checks = {
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
