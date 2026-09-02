{
  buildGoModule,
  podman,
}:
buildGoModule {
  pname = "quadlet";
  inherit (podman) version src;
  vendorHash = null;
  subPackages = [ "cmd/quadlet" ];
  # Go map iteration makes generated flags nondeterministic, so sort the maps
  # to prevent spurious unit changes and service restarts.
  patches = [ ./patches/quadlet-sorted-flags.patch ];
  # The upstream command test does not exercise generated unit ordering.
  doCheck = false;
  env.CGO_ENABLED = 0;
  meta.mainProgram = "quadlet";
}
