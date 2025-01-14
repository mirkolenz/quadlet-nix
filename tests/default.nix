{ lib, self, ... }:
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
      checks = lib.genAttrs [ "nixos" ] (
        name:
        pkgs.testers.runNixOSTest {
          inherit name;
          imports = [ ./${name}.nix ];
          defaults =
            { pkgs, ... }:
            {
              imports = [ self.nixosModules.quadlet ];
              environment.systemPackages = with pkgs; [ curl ];
              virtualisation.quadlet.enable = true;
              virtualisation = {
                graphics = false;
                cores = 4;
                memorySize = 4096;
              };
              # Workaround for the following error:
              # Kernel panic - not syncing: IO-APIC + timer doesn't work!
              # Boot with apic=debug and send a report.
              # Then try booting with the 'noapic' option.
              boot.kernelParams = [ "noapic" ];
            };
        }
      );
    };
}
