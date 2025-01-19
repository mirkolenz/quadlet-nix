# quadlet-nix

NixOS module for [Quadlet / podman-systemd](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html).
Inspired by the excellent work of [SEIAROTg](https://github.com/SEIAROTg/quadlet-nix), but rewritten from scratch.
You can get started with the following minimal configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    quadlet-nix = {
      url = "github:mirkolenz/quadlet-nix/v1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {nixpkgs, flocken, ...}:  {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({pkgs, ...}: {
          virtualisation.quadlet.enable = true;
          virtualisation.quadlet.containers = {
            hello-world = {
              containerConfig.Image = "docker.io/library/hello-world:latest";
            };
            nginx = {
              imageStream = pkgs.dockerTools.examples.nginxStream;
            };
          };
        })
      ];
    };
  };
}
```

All available options are described in the [documentation](https://mirkolenz.github.io/quadlet-nix/options.html).
You may also want to take a look at the [tests](./tests/nixos.nix) for more examples.
