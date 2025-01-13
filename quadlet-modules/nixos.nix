{
  lib,
  config,
  ...
}:
{
  options = {
    uid = lib.mkOption {
      type = with lib.types; nullOr int;
      example = 1000;
      default = null;
    };
  };
  config = lib.mkIf (config.uid != null) {
    autoStartTarget = lib.mkIf (config.uid == null) "multi-user.target";
    unitConfig.ConditionUser = config.uid;
  };
}
