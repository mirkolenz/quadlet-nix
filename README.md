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
  outputs = { nixpkgs, quadlet-nix, ... }: {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        quadlet-nix.nixosModules.default
        ({ pkgs, config, ... }: {
          virtualisation.quadlet.enable = true;
          virtualisation.quadlet.images.nginx.package = pkgs.dockerTools.examples.nginxStream;
          virtualisation.quadlet.containers = {
            hello-world = {
              containerConfig.Image = "docker.io/library/hello-world:latest";
            };
            nginx.containerConfig.Image = config.virtualisation.quadlet.images.nginx.ref;
          };
        })
      ];
    };
  };
}
```

All available options are described in the [documentation](https://mirkolenz.github.io/quadlet-nix/index.html).
You may also want to take a look at the [tests](https://github.com/mirkolenz/quadlet-nix/blob/main/dev/tests/nixos.nix) for more examples.
Once there are units, the NixOS module enables `virtualisation.podman` and the Home Manager module enables `services.podman`, whose `package` both use for generating the units.
Note that `services.podman` writes its own `containers.conf`, `storage.conf`, `registries.conf` and `policy.json` into `~/.config/containers`, which take precedence over those of the system in `/etc/containers`.

## Rootless units

`uid` selects the systemd manager that owns a unit.
`null` installs a system unit and runs Podman rootfully, a positive UID installs a user unit for that UID's systemd user manager, and `uid = 0` is rejected because a rootful unit is expressed as `null`.
The Home Manager module has no `uid` option at all, since a Home Manager configuration always covers exactly one user.

This is unrelated to the identity inside the container, which is configured with the native Quadlet keys `User=`, `UserNS=`, `UIDMap=`, `GIDMap=`, `SubUIDMap=`, and `SubGIDMap=`.
Creating the user account, enabling lingering, and allocating subordinate UID/GID ranges stay your responsibility:

```nix
users.users.app = {
  isSystemUser = true;
  uid = 990;
  group = "app";
  home = "/var/lib/app";
  createHome = true;
  linger = true;
  autoSubUidGidRange = true;
};

virtualisation.quadlet.containers.web = {
  uid = config.users.users.app.uid;
  containerConfig.Image = "docker.io/library/nginx:latest";
};
```

## Managing units with `quadletctl`

Both modules install the `quadletctl` command, which knows every enabled unit from the configuration and dispatches it to the systemd manager, journal, and Podman storage of its owner.
Each subcommand forwards its trailing arguments verbatim to the underlying command, so all of its flags keep working:

```console
$ quadletctl list                                   # owner, kind, podman name, and state of all units
$ quadletctl systemctl restart web                  # systemctl [--user] restart web.service
$ quadletctl journalctl web -f                      # journalctl --unit= or --user-unit=web.service
$ quadletctl podman web exec -it systemd-web sh     # podman as the owner of web
$ quadletctl shell web                              # shell as the owner of web
```

Units of other users require root or polkit authorization, while their accounts need neither a login shell nor journal permissions.
The NixOS and Home Manager modules install the table of their units as `quadletctl/units.tsv` into `/etc/xdg` and `~/.config`, where `quadletctl` finds it via the XDG config directories.
The command comes with help, man pages, and completions of the unit names for bash, fish, and zsh.
Set `virtualisation.quadlet.quadletctl.enable = false` to omit it.

## Quoting values

For keys that hold `KEY=VALUE` assignments (e.g., `Environment`, `Label`, `Annotation`), use the attrset form so the entries are quoted automatically.
Quote dotted keys, since Nix would otherwise parse them as nested attrsets:

```nix
containerConfig.Environment = { TZ = "Europe/Berlin"; };
containerConfig.Label = { "org.opencontainers.image.title" = "My web server"; };
```

List entries are written verbatim, so use the attrset form for `KEY=VALUE` pairs.
The list form is needed for entries without a value, which Podman passes through from the service environment (e.g., to keep secrets out of the Nix store).
Both forms can be combined via `lib.mkMerge` or separate definitions:

```nix
serviceConfig.EnvironmentFile = "/run/secrets/web.env";
containerConfig.Environment = lib.mkMerge [
  { TZ = "Europe/Berlin"; }
  [ "API_TOKEN" ]
];
```

All other values are written into the unit file verbatim.
Whitespace and quotes are handled by Quadlet itself when it builds the resulting `ExecStart=` line, so no additional quoting is required.
systemd still expands specifiers and variables in it, so write a literal `%` as `%%` and a literal `$` as `$$`.

## Nix-built images

A container with an `imagePackage`, an archive (e.g., `pkgs.dockerTools.buildLayeredImage`) or a stream (e.g., `pkgs.dockerTools.streamLayeredImage`), runs that image instead of pulling one:

```nix
virtualisation.quadlet.containers.web.imagePackage = pkgs.dockerTools.examples.nginxStream;
```

An entry of `images` takes the same image as its `package`, so other units can reference the image through Quadlet's `Image=<name>.image`, best spelled as its read-only `ref` so a typo fails evaluation:

```nix
virtualisation.quadlet = {
  images.web.package = pkgs.dockerTools.examples.nginxStream;
  containers.web.containerConfig.Image = config.virtualisation.quadlet.images.web.ref;
  volumes.web-content.volumeConfig = {
    Driver = "image";
    Image = config.virtualisation.quadlet.images.web.ref;
  };
};
```

Either way, the image is loaded before the unit starts unless this build is already present.
Podman loads it with `podman pull` from a `docker-archive:` and tags it as `localhost/quadlet/<imageName>:<hash>`, the `podmanName` of an image unit.
The hash of its store path tells the builds apart, even when they set a fixed tag such as `latest`, so the name stored in the archive is removed again.
The load receives the `GlobalArgs=` and `ContainersConfModule=` of the unit, so it uses the same storage.
Still configure a custom storage location in `storage.conf`, since the prune timer and `quadletctl` only know the storage of each owner.
A container running such an image gets `AutoUpdate=disabled`, since no registry provides it, and is updated by rebuilding instead.

`imagePackage` is a shortcut for an image that a single container uses.
An image shared by several units belongs in `images`, so that it is loaded once.
The container options `imageFile` and `imageStream` are deprecated in favor of `imagePackage`.

## Updates and pruning

`autoUpdate.enable` adds the `quadlet-update` timer, scheduled at `autoUpdate.startAt`, which runs the `podman-auto-update` service that Podman ships.
It updates and restarts the containers labeled with `AutoUpdate=`, and then prunes dangling images.
A drop-in limits a run of the service to 15 minutes, while the `podman-auto-update` timer of Podman stays untouched.
On NixOS, a user manager only runs the timer for the owners of rootless units.
With Home Manager, `services.podman.autoUpdate` is disabled by default and cannot be enabled together with `autoUpdate`, since it defines a service of the same name.

Previous versions of an image stay tagged, both pulled ones such as `v2.1` after switching to `v3.0` and previous Nix builds, so the prune of every auto-update keeps them.
`autoPrune.enable` adds the `quadlet-prune` timer, scheduled at `autoPrune.startAt`, which removes every image that no container uses with `podman image prune --all`.
Unlike `virtualisation.podman.autoPrune` with `--all`, it covers rootless owners and Home Manager, and leaves alone the networks of Quadlet units, which `podman system prune` would remove.
As with any such prune, the image of a stopped unit is pulled or loaded again when it starts.

## Resource units

Images, volumes, networks, builds and artifacts are created when a unit that references them starts, as Quadlet adds the `Requires=` itself, so their `autoStart` defaults to false.
Long-running units (`.container`, `.kube`, `.pod`) default to starting at boot, except for a container or kube with `serviceConfig.Type = "oneshot"`, which runs to completion like a resource.
Set `autoStart = true` to run it at boot anyway.

## Restart and rate-limit defaults

For long-running units (`.container`, `.kube`, `.pod`) the module sets a few `[Service]` / `[Unit]` keys to replace systemd defaults that are unsafe for containers.
Any value set in `serviceConfig` or `unitConfig` takes precedence, and a container or kube with `serviceConfig.Type = "oneshot"` runs to completion and keeps systemd's defaults.

| Key                                         | Default      | Reason                                                                             |
| ------------------------------------------- | ------------ | ---------------------------------------------------------------------------------- |
| `Restart`                                   | `on-failure` | Systemd's `no` means containers don't auto-restart at all.                         |
| `RestartSec`                                | `5s`         | Systemd's `100ms` paired with `Restart=` produces millisecond-scale restart loops. |
| `TimeoutStartSec`                           | `900s`       | Systemd's `90s` is often too short for image pulls or cold-start workloads.        |
| `StartLimitBurst` / `StartLimitIntervalSec` | `3` / `600s` | Refuse a 4th start within 10 minutes so a broken unit doesn't loop forever.        |

The burst limit only fires when `(TimeoutStartSec + RestartSec) × StartLimitBurst ≤ StartLimitIntervalSec`, which holds for typical fast-starting services.
A unit that consistently hangs all the way to `TimeoutStartSec` will retry indefinitely because each attempt falls outside the rate-limit window.
Tighten `TimeoutStartSec` (or widen `StartLimitIntervalSec`) downstream when you want hung-start loops to hard-fail.

## Overriding the generated unit

Each `*Config` section passes its keys through verbatim, so any Quadlet key can be set directly under its section using the upstream `PascalCase` name.
For the rare cases this does not cover, two escape hatches are available.

`extraConfig` is a freeform set of `[Section]` keys merged over the generated unit and takes precedence, so it can override a value the module sets itself:

```nix
# Any [Section], any value, written through with the last word:
extraConfig.Service.TimeoutStartSec = "300";
```

`rawConfig` replaces the entire unit file with the given text, bypassing generation completely:

```nix
rawConfig = ''
  [Container]
  Image=docker.io/library/hello-world:latest
'';
```

## Comparison to [SEIAROTg/quadlet-nix](https://github.com/SEIAROTg/quadlet-nix)

The two implementations solve the same problem but make different trade-offs.
The clearest difference is where unit correctness is checked: this version validates at build time, the original at evaluation time.

### Where this version differs

- Unit files are produced inside a Nix derivation by invoking `podman-system-generator` / `podman-user-generator` at build time, rather than relying on the systemd generator at boot.
  The resulting package is added to `systemd.packages`.
  The generator is built from the podman sources with its flag ordering made deterministic, so a regenerated unit only changes when its configuration does and nothing else is restarted on activation.
- Quadlet keys are passed through verbatim using their original `PascalCase` names (e.g., `containerConfig.Image`, `containerConfig.PublishPort`).
  The upstream Podman documentation applies directly and new Quadlet keys work without changes to this module.
- Because the generator runs at build time, podman itself validates the units and the build aborts unless every expected unit is emitted.
  Errors the generator would otherwise log and skip at boot become hard build failures, checked by the same tool that consumes the units instead of by option types that have to be kept in sync with upstream.
- Rootless containers are supported directly from the NixOS module by setting a `uid` per object, Home Manager is not required.
  See [Rootless units](#rootless-units).
- Container images can be supplied as Nix packages (e.g., `pkgs.dockerTools.streamLayeredImage`) via the `package` option of an image unit.
- Releases follow semantic versioning with version tags (e.g., `v1`) for stable pinning and the flake is structured with [flake-parts](https://flake.parts).
- Long-running units (`.container`, `.kube`, `.pod`) ship with overridable restart and rate-limit settings.

### Where the original may suit you better

- Each Quadlet key is exposed as a dedicated, individually typed and documented option (e.g., `containerConfig.publishPorts : listOf str`), giving you per-field type checking and inline help.
- That typing catches structural mistakes earlier, during evaluation rather than at build time, e.g., rejecting `Exec = [ "a" "b" ]` since Quadlet only honors a single value.
- Longer track record and a more elaborate README with recipes and comparisons to other tools.
