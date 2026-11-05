{
  description = "NixOS, system-manager and Home Manager modules for Quadlet / podman-systemd";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };
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
          ./docs
        ];
        flake.lib = import ./lib.nix lib;
        perSystem =
          { pkgs, config, ... }:
          {
            legacyPackages = {
              # A minimal system of Quadlet configured by `modules`, whose
              # `virtualisation.quadlet.bundle` is for a host without Nix.
              mkBundleSystem =
                { modules }:
                inputs.nixpkgs.lib.nixosSystem {
                  modules = [
                    self.nixosModules.default
                    {
                      nixpkgs.pkgs = pkgs;
                      system.stateVersion = lib.trivial.release;
                      boot.isContainer = true;
                      virtualisation.quadlet.enable = true;
                    }
                  ]
                  ++ modules;
                };
              mkBundle =
                args: (config.legacyPackages.mkBundleSystem args).config.virtualisation.quadlet.bundle.package;
            };
          };
        partitionedAttrs = {
          checks = "dev";
          formatter = "dev";
          nixosConfigurations = "dev";
        };
        partitions.dev = {
          extraInputsFlake = ./dev;
          module = ./dev;
        };
      }
    );
}
