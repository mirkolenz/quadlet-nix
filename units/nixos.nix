{
  lib,
  config,
  ...
}:
{
  options = {
    uid = lib.mkOption {
      type = with lib.types; nullOr ints.positive;
      example = 1000;
      default = null;
      description = ''
        UID of the systemd user manager that owns this Quadlet.
        When null, it becomes a system unit and Podman runs rootfully.
        This selects the systemd manager only, not the identity inside the container.
      '';
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
