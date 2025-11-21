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
    ${lib.getExe podman} image prune --all --force
  '';
  serviceConfig = {
    Type = "oneshot";
    TimeoutStartSec = 900;
    TimeoutStopSec = 10;
  };
  unitConfig = lib.mkIf (conditionUsers != null && lib.length conditionUsers > 0) {
    ConditionUser = lib.concatMapStringsSep "|" toString conditionUsers;
  };
}
