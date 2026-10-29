{
  config,
  lib',
  lib,
  nixImageLoad,
  ...
}:
{
  options = {
    imageConfig = lib'.mkQuadletSectionOption {
      anchor = "image-units-image";
      description = "The systemd image configuration (the `[Image]` section)";
    };
    package = lib'.mkNixImageOption "A Nix-built image to load instead of pulling `imageConfig.Image`";
  };
  config = lib.mkMerge [
    {
      kind = "image";
      serviceName = lib.defaultTo "${config.name}-image" (config.imageConfig.ServiceName or null);
      # What Quadlet resolves `Image=<name>.image` to.
      podmanName = config.imageConfig.ImageTag or config.imageConfig.Image or null;

      finalConfig.Image = config.imageConfig;
    }
    # The pull then finds the loaded image in local storage. Loading needs no
    # network, and, without `RemainAfterExit=`, every start of a container
    # checks that the image still exists.
    (lib.mkIf (config.package != null) {
      imageConfig = {
        Image = lib'.nixImageReference config.package;
        Policy = "missing";
      };
      serviceConfig = {
        ExecStartPre = [ (nixImageLoad config.package config.imageConfig) ];
        RemainAfterExit = lib.mkDefault false;
      };
      quadletConfig.DefaultDependencies = lib.mkDefault false;
    })
  ];
}
