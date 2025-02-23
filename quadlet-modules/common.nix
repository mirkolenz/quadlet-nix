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
      type = lib.types.str;
      description = "The name of the podman object";
    };
    ref = lib.mkOption {
      readOnly = true;
      type = lib.types.str;
      description = "The reference of the podman object (i.e., the filename)";
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
      default = true;
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
      internal = true; # no longer needed, but kept for compatibility
      description = "The systemd install configuration";
    };
    quadletConfig = lib'.mkSectionOption {
      description = "The systemd quadlet configuration";
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
  config = {
    finalConfig = {
      Unit = config.unitConfig;
      Install = config.installConfig;
      Service = config.serviceConfig;
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
