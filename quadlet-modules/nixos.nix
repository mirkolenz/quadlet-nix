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
      description = "The user ID to run the service as.";
    };
  };
  config = lib.mkMerge [
    (lib.mkIf (config.uid == null) {
      autoStartTarget = "multi-user.target";
    })
    (lib.mkIf (config.uid != null) {
      unitConfig.ConditionUser = config.uid;
    })
  ];
}
