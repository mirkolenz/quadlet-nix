{
  podman,
  lib,
  startAt,
  autoStartTarget,
  conditionUsers,
}:
{
  description = "Quadlet auto-update";
  wantedBy = [ autoStartTarget ];
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
  unitConfig.ConditionUser = lib.mkIf (lib.length conditionUsers > 0) (
    lib.concatMapStringsSep "|" toString conditionUsers
  );
}
