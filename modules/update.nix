{
  podman,
  lib,
  defaultTarget,
  startAt,
}:
{
  description = "Quadlet auto-update";
  wantedBy = [ defaultTarget ];
  wants = [ "network-online.target" ];
  after = [ "network-online.target" ];
  inherit startAt;
  serviceConfig = {
    Type = "oneshot";
    Environment = "PATH=/run/wrappers/bin:/usr/bin";
    ExecStart = "${lib.getExe podman} auto-update";
    ExecStartPost = "${lib.getExe podman} image prune -f";
    TimeoutStartSec = 900;
    TimeoutStopSec = 10;
  };
}
