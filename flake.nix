{
  description = "NixOS, system-manager and Home Manager modules for Quadlet / podman-systemd";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { lib, self, ... }:
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        imports = [
          flake-parts.flakeModules.partitions
          ./modules
        ];
        flake.lib = import ./lib.nix lib // {
          # A minimal system of Quadlet configured by `modules` with `pkgs`,
          # whose `virtualisation.quadlet.bundle` is for a host without Nix.
          mkBundleSystem =
            { pkgs, modules }:
            pkgs.nixos (
              [
                self.nixosModules.default
                {
                  system.stateVersion = pkgs.lib.trivial.release;
                  boot.isContainer = true;
                  virtualisation.quadlet.enable = true;
                }
              ]
              ++ modules
            );
          mkBundle = args: (self.lib.mkBundleSystem args).config.virtualisation.quadlet.bundle.package;
        };
        partitionedAttrs = {
          checks = "dev";
          formatter = "dev";
          nixosConfigurations = "dev";
          packages = "dev";
        };
        partitions.dev = {
          extraInputsFlake = ./dev;
          module = ./dev;
        };
      }
    );
}
