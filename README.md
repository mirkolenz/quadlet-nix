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

## Restart and rate-limit defaults

For long-running units (`.container`, `.kube`, `.pod`) the module sets a few `[Service]` / `[Unit]` keys as `lib.mkDefault` to replace systemd defaults that are unsafe for containers.

| Key | Default | Reason |
|-----|---------|--------|
| `Restart` | `on-failure` | Systemd's `no` means containers don't auto-restart at all. |
| `RestartSec` | `5s` | Systemd's `100ms` paired with `Restart=` produces millisecond-scale restart loops. |
| `TimeoutStartSec` | `900s` | Systemd's `90s` is often too short for image pulls or cold-start workloads. |
| `StartLimitBurst` / `StartLimitIntervalSec` | `3` / `600s` | Hard-fail after 3 restarts in 10 minutes so a broken unit doesn't loop forever. |

The burst limit only fires when `(TimeoutStartSec + RestartSec) × StartLimitBurst ≤ StartLimitIntervalSec`, which holds for typical fast-starting services.
A unit that consistently hangs all the way to `TimeoutStartSec` will retry indefinitely because each attempt falls outside the rate-limit window.
Tighten `TimeoutStartSec` (or widen `StartLimitIntervalSec`) downstream when you want hung-start loops to hard-fail.

## Comparison to [SEIAROTg/quadlet-nix](https://github.com/SEIAROTg/quadlet-nix)

- Unit files are produced inside a Nix derivation by invoking `podman-system-generator` / `podman-user-generator` at build time, rather than relying on the systemd generator at boot. The resulting package is added to `systemd.packages`.
- Rootless containers are supported directly from the NixOS module by setting a `uid` per object, Home Manager is not required.
- Quadlet keys keep their upstream `PascalCase` names (e.g., `containerConfig.Image`) but are still fully typed to catch errors during evaluation. Brand-new keys still pass through verbatim by the use of freeform submodules.
- A `quadlet-drift` flake check (`nix run .#quadlet-drift`) diffs the declared options against the pinned `podman` source, so the typed options stay aligned with upstream.
- Container images can be supplied as Nix packages via `imageFile` (e.g., `pkgs.dockerTools.buildImage`) or `imageStream` (e.g., `pkgs.dockerTools.streamLayeredImage`).
- Releases follow semantic versioning with version tags (e.g., `v1`) for stable pinning and the flake is structured with [flake-parts](https://flake.parts).
- Long-running units (`.container`, `.kube`, `.pod`) ship with overridable restart and rate-limit settings.
