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
    };
    podmanName = lib.mkOption {
      readOnly = true;
      type = lib.types.str;
    };
    ref = lib.mkOption {
      readOnly = true;
      type = lib.types.str;
    };
    text = lib.mkOption {
      readOnly = true;
      type = lib.types.str;
    };

    # internal options
    systemdConfig = lib.mkOption {
      internal = true;
      type = lib.types.attrsOf lib'.unitOption;
    };
    autoStartTarget = lib.mkOption {
      internal = true;
      type = lib.types.str;
      default = "default.target";
    };

    # regular options
    name = lib.mkOption {
      type = lib.types.str;
      default = name;
    };
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    # unit options
    unitConfig = lib'.mkUnitOption { };
    serviceConfig = lib'.mkUnitOption { };
    installConfig = lib'.mkUnitOption { };
    quadletConfig = lib'.mkUnitOption { };
  };
  config = {
    installConfig = {
      WantedBy = lib.mkIf config.autoStart [ config.autoStartTarget ];
    };
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
  };
}
