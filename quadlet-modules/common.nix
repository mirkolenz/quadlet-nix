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
    systemdConfig = lib.mkOption {
      internal = true;
      type = lib.types.attrsOf lib'.unitOption;
      description = "The merged systemd unit configuration";
    };
    autoStartTarget = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "default.target";
      description = "The systemd target to start the service at";
    };

    # regular options
    name = lib.mkOption {
      type = lib.types.str;
      default = name;
      description = "The name of the systemd unit";
    };
    autoStart = (lib.mkEnableOption "service auto-start") // {
      default = true;
    };

    # unit options
    unitConfig = lib'.mkUnitOption {
      description = "The systemd unit configuration";
    };
    serviceConfig = lib'.mkUnitOption {
      description = "The systemd service configuration";
    };
    installConfig = lib'.mkUnitOption {
      description = "The systemd install configuration";
    };
    quadletConfig = lib'.mkUnitOption {
      description = "The systemd quadlet configuration";
    };

    # nix-specific install options
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
    serviceConfig = {
      Restart = "always";
      TimeoutStartSec = lib.mkDefault 900;
    };
    systemdConfig = {
      Unit = config.unitConfig;
      Install = config.installConfig;
      Service = config.serviceConfig;
      Quadlet = config.quadletConfig;
    };
    text = lib'.mkUnitText config.systemdConfig;
    wantedBy = lib.mkIf config.autoStart [ config.autoStartTarget ];
  };
}
