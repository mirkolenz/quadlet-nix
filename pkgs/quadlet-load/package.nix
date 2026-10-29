{
  lib,
  writeShellApplication,
  skopeo,
}:
writeShellApplication {
  name = "quadlet-load";
  text = lib.readFile ./script.sh;
  runtimeInputs = [ skopeo ];
}
