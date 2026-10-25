{
  lib,
  name,
  config,
  lib',
  ...
}:
{
  options = {
    # readonly options
    serviceName = lib.mkOption {
      readOnly = true;
      type = lib.types.str;
      description = "The name of the systemd service (without the .service suffix)";
    };
    podmanName = lib.mkOption {
      readOnly = true;
      type = lib.types.nullOr lib.types.str;
      description = "The name of the podman object, such as the container name or the image an image or build unit stores, or null if a `rawConfig` hides it";
    };
    kind = lib.mkOption {
      internal = true;
      readOnly = true;
      type = lib.types.str;
      description = "The kind of podman object (i.e., the unit file extension)";
    };
    owner = lib.mkOption {
      internal = true;
      readOnly = true;
      type = lib.types.strMatching "system|user|[0-9]+";
      description = "The systemd manager of the unit, which is `system`, `user` for the configured user, or a UID";
    };
    ref = lib.mkOption {
      readOnly = true;
      type = lib.types.str;
      description = "The Quadlet file name, such as `web.image`, through which other units reference this one (e.g., `Image=`, `Network=`, `Volume=` or `Pod=`)";
    };
    text = lib.mkOption {
      readOnly = true;
      type = lib.types.str;
      description = "The generated systemd unit file text";
    };

    # internal options
    # finalConfig is called `unit` in nixpkgs
    finalConfig = lib'.mkUnitOption {
      internal = true;
      description = "The merged systemd unit configuration";
    };
    longRunning = lib.mkOption {
      internal = true;
      type = lib.types.bool;
      default = false;
      description = "Whether the unit runs a workload instead of creating a resource";
    };
    autoStartTarget = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "default.target";
      description = "The systemd target to start the service at";
    };

    # regular options
    enable = (lib.mkEnableOption "the service") // {
      default = true;
    };
    name = lib.mkOption {
      type = lib.types.str;
      default = name;
      description = "The attribute name used to derive the other names";
    };
    autoStart = (lib.mkEnableOption "service auto-start") // {
      default = config.longRunning;
      defaultText = lib.literalMD "whether the unit runs a workload, unlike a resource that its dependents start";
    };
    extraConfig = lib'.mkUnitOption {
      description = "Additional systemd unit configuration";
    };
    rawConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = "Raw systemd unit configuration text";
    };

    # unit options
    unitConfig = lib'.mkSectionOption {
      description = "The systemd unit configuration";
    };
    serviceConfig = lib'.mkSectionOption {
      description = "The systemd service configuration";
    };
    installConfig = lib'.mkSectionOption {
      internal = true;
      description = "Deprecated, use `wantedBy`, `requiredBy`, `upheldBy` and `aliases` instead";
    };
    quadletConfig = lib'.mkQuadletSectionOption {
      anchor = "quadlet-section-quadlet";
      description = "The systemd quadlet configuration (the `[Quadlet]` section)";
    };

    # nix-specific options
    # https://github.com/NixOS/nixpkgs/blob/master/nixos/lib/systemd-unit-options.nix
    aliases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "The list of aliases for the systemd unit";
    };
    wantedBy = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "The list of systemd targets to install the unit into";
    };
    requiredBy = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "The list of systemd targets that require the unit";
    };
    upheldBy = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "The list of systemd targets that uphold the unit";
    };
  };
  config =
    let
      # Applied beneath the sections rather than as `mkDefault` definitions of
      # them, since containers and kubes read `Type` from them for `longRunning`.
      defaults = section: values: lib.optionalAttrs config.longRunning values // section;
    in
    {
      ref = "${config.name}.${config.kind}";
      unitConfig.Description = lib.mkDefault "Podman ${config.kind} ${config.name}";
      finalConfig = {
        Unit = defaults config.unitConfig {
          StartLimitBurst = 3;
          StartLimitIntervalSec = 600;
        };
        Install = config.installConfig;
        Service = defaults config.serviceConfig {
          Restart = "on-failure";
          RestartSec = 5;
          TimeoutStartSec = 900;
        };
        Quadlet = config.quadletConfig;
      };
      text =
        if config.rawConfig != null then
          config.rawConfig
        else
          lib'.mkUnitText (lib.recursiveUpdate config.finalConfig config.extraConfig);
      wantedBy = lib.mkIf config.autoStart [ config.autoStartTarget ];
    };
}
