{
  lib,
  writeShellApplication,
  skopeo,
}:
writeShellApplication {
  name = "quadlet-nix-image-load";
  text = lib.readFile ./script.sh;
  runtimeInputs = [ skopeo ];
}
