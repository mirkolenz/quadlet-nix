{
  config,
  lib',
  lib,
  ...
}:
let
  inherit (lib') mkQuadletOption singleOrList;
  inherit (lib.types) str int bool;
in
{
  options = {
    imageConfig = lib'.mkQuadletSectionOption {
      anchor = "image-units-image";
      description = "The systemd image configuration (the `[Image]` section)";
      options = {
        AllTags = mkQuadletOption {
          type = bool;
          flag = "--all-tags";
        };
        Arch = mkQuadletOption {
          type = str;
          flag = "--arch";
          example = "aarch64";
        };
        AuthFile = mkQuadletOption {
          type = str;
          flag = "--authfile";
          example = "/etc/registry/auth.json";
        };
        CertDir = mkQuadletOption {
          type = str;
          flag = "--cert-dir";
          example = "/etc/registry/certs";
        };
        ContainersConfModule = mkQuadletOption {
          type = singleOrList str;
          flag = "--module";
          example = [ "/etc/nvd.conf" ];
        };
        Creds = mkQuadletOption {
          type = str;
          flag = "--creds";
          example = "myname:mypassword";
        };
        DecryptionKey = mkQuadletOption {
          type = str;
          flag = "--decryption-key";
          example = "/etc/registry.key";
        };
        GlobalArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--log-level=debug" ];
        };
        Image = mkQuadletOption {
          type = str;
          example = "quay.io/centos/centos:latest";
        };
        ImageTag = mkQuadletOption {
          type = str;
          example = "quay.io/centos/centos:latest";
        };
        OS = mkQuadletOption {
          type = str;
          flag = "--os";
          example = "windows";
        };
        PodmanArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--os=linux" ];
        };
        Policy = mkQuadletOption {
          type = str;
          flag = "--policy";
          example = "always";
        };
        Retry = mkQuadletOption {
          type = int;
          flag = "--retry";
          example = 5;
        };
        RetryDelay = mkQuadletOption {
          type = str;
          flag = "--retry-delay";
          example = "10s";
        };
        ServiceName = mkQuadletOption {
          type = str;
          example = "name";
        };
        TLSVerify = mkQuadletOption {
          type = bool;
          flag = "--tls-verify";
        };
        Variant = mkQuadletOption {
          type = str;
          flag = "--variant";
          example = "arm/v7";
        };
      };
    };
  };
  config = {
    ref = "${config.name}.image";
    serviceName = lib.defaultTo "${config.name}-image" config.imageConfig.ServiceName;
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman image ${config.name}";

    finalConfig.Image = config.imageConfig;
  };
}
