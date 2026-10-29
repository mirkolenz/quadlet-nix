{
  lib,
  config,
  lib',
  images,
  nixImageLoad,
  ...
}:
let
  # The deprecated options, which `imagePackage` replaces.
  deprecatedImage = lib.defaultTo config.imageStream config.imageFile;

  # No registry provides a Nix-built image, either of its own or of an image unit.
  runsNixImage =
    config.imagePackage != null
    || lib.any (image: image.package != null && image.ref == config.containerConfig.Image or null) (
      lib.attrValues images
    );
in
{
  options = {
    containerConfig = lib'.mkQuadletSectionOption {
      anchor = "container-units-container";
      description = "The systemd container configuration (the `[Container]` section)";
    };
    imagePackage = lib'.mkNixImageOption "A Nix-built image the container runs instead of `containerConfig.Image`";
    imageFile = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "Deprecated, use `imagePackage`.";
    };
    imageStream = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "Deprecated, use `imagePackage`.";
    };
  };
  config = {
    kind = "container";
    # A oneshot runs to completion, like a resource.
    longRunning = config.serviceConfig.Type or null != "oneshot";
    serviceName = lib.defaultTo "${config.name}" (config.containerConfig.ServiceName or null);
    # Quadlet names the container after the service, as `systemd-%N`.
    podmanName = lib.defaultTo "systemd-${config.serviceName}" (
      config.containerConfig.ContainerName or null
    );
    imagePackage = lib.mkIf (deprecatedImage != null) deprecatedImage;
    containerConfig.Image = lib.mkIf (config.imagePackage != null) (
      lib'.nixImageReference config.imagePackage
    );
    serviceConfig.ExecStartPre = lib.mkIf (config.imagePackage != null) [
      (nixImageLoad config.imagePackage config.containerConfig)
    ];

    finalConfig.Container =
      config.containerConfig // lib.optionalAttrs runsNixImage { AutoUpdate = "disabled"; };
  };
}
