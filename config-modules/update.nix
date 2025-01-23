{
  podman,
  lib,
  startAt,
  conditionUsers ? null,
}:
{
  description = "Quadlet auto-update";
  wants = [ "network-online.target" ];
  after = [ "network-online.target" ];
  inherit startAt;
  script = ''
    ${lib.getExe podman} auto-update
    ${lib.getExe podman} image prune -f
  '';
  serviceConfig = {
    Type = "oneshot";
    TimeoutStartSec = 900;
    TimeoutStopSec = 10;
  };
  unitConfig.ConditionUser = lib.mkIf (conditionUsers != null && lib.length conditionUsers > 0) (
    lib.concatMapStringsSep "|" toString conditionUsers
  );
}
