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

All available options are described in the [documentation](https://mirkolenz.github.io/quadlet-nix/nixos-options.html).
You may also want to take a look at the [tests](https://github.com/mirkolenz/quadlet-nix/blob/main/tests/nixos.nix) for more examples.

## Quoting values

For keys that hold `KEY=VALUE` assignments (e.g., `Environment`, `Label`, `Annotation`), use the attrset form so the entries are quoted automatically:

```nix
containerConfig.Environment = { TZ = "Europe/Berlin"; };
containerConfig.Label = { description = "My web server"; };
```

The same result can be expressed via the list form with `lib.strings.toJSON`, which is useful when an attrset cannot represent the value (e.g., duplicate keys):

```nix
containerConfig.Label = [ (lib.strings.toJSON "description=My web server") ];
```

All other values are written into the unit file verbatim.
Whitespace and other special characters are handled by Quadlet itself when it builds the resulting `ExecStart=` line, so no additional quoting is required.

## Comparison to [SEIAROTg/quadlet-nix](https://github.com/SEIAROTg/quadlet-nix)

The two implementations solve the same problem but make different trade-offs.

### Where this version differs

- Unit files are produced inside a Nix derivation by invoking `podman-system-generator` / `podman-user-generator` at build time, rather than relying on the systemd generator at boot.
  The resulting package is added to `systemd.packages`.
- Rootless containers are supported directly from the NixOS module by setting a `uid` per object, Home Manager is not required.
- Quadlet keys are passed through verbatim using their original `PascalCase` names (e.g., `containerConfig.Image`, `containerConfig.PublishPort`).
  The upstream Podman documentation applies directly and new Quadlet keys work without changes to this module.
- Container images can be supplied as Nix packages via `imageFile` (e.g., `pkgs.dockerTools.buildImage`) or `imageStream` (e.g., `pkgs.dockerTools.streamLayeredImage`).
- Releases follow semantic versioning with version tags (e.g., `v1`) for stable pinning and the flake is structured with [flake-parts](https://flake.parts).

### Where the original may suit you better

- Each Quadlet key is exposed as a dedicated, individually typed and documented option (e.g., `containerConfig.publishPorts : listOf str`), giving you per-field type checking and inline help.
- Per-key typing catches structural mistakes at eval time, e.g., rejecting `Exec = [ "a" "b" ]` since Quadlet only honors the last line.
- Longer track record and a more elaborate README with recipes and comparisons to other tools.
