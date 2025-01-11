{
  lib,
  name,
  config,
  lib',
  ...
}:
{
  options = {
    serviceName = lib.mkOption { readOnly = true; };
    podmanName = lib.mkOption { readOnly = true; };
    ref = lib.mkOption { readOnly = true; };
    text = lib.mkOption { readOnly = true; };

    name = lib.mkOption {
      type = lib.types.str;
      default = name;
    };
    uid = lib.mkOption {
      type = with lib.types; nullOr int;
      example = 1000;
      default = null;
    };
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    systemdConfig = lib.mkOption {
      type = lib.types.attrsOf lib'.unitOption;
    };

    unitConfig = lib'.mkUnitOption { };
    serviceConfig = lib'.mkUnitOption { };
    installConfig = lib'.mkUnitOption { };
    quadletConfig = lib'.mkUnitOption { };
  };
  config = {
    installConfig = {
      WantedBy = lib.mkIf config.autoStart (
        if config.uid == null then [ "multi-user.target" ] else [ "default.target" ]
      );
    };
    serviceConfig = {
      Restart = "always";
      # podman rootless requires "newuidmap" (the suid version, not the non-suid one from pkgs.shadow)
      Environment = "PATH=/run/wrappers/bin:/usr/bin";
      TimeoutStartSec = lib.mkDefault 900;
    };
    systemdConfig = {
      Unit = config.unitConfig;
      Install = config.installConfig;
      Service = config.serviceConfig;
      Quadlet = config.quadletConfig;
    };
    unitConfig = {
      ConditionUser = lib.mkIf (config.uid != null) config.uid;
    };
    text = lib'.mkUnitText config.systemdConfig;
  };
}
