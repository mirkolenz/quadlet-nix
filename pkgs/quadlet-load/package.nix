{
  lib,
  writeShellApplication,
  podman,
}:
writeShellApplication {
  name = "quadlet-load";
  text = lib.readFile ./script.sh;
  runtimeInputs = [ podman ];
}
