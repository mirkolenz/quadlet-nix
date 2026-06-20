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
    artifactConfig = lib'.mkQuadletSectionOption {
      anchor = "artifact-units-artifact";
      description = ''
        The systemd artifact configuration (the `[Artifact]` section)

        WARNING: Experimental Unit. This unit is considered experimental and still in development. Inputs, options, and outputs are all subject to change.
      '';
      options = {
        Artifact = mkQuadletOption {
          type = str;
          example = "quay.io/foobar/artifact:special";
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
          example = "username:password";
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
        PodmanArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--pull never" ];
        };
        Quiet = mkQuadletOption {
          type = bool;
          flag = "--quiet";
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
          example = "my-artifact";
        };
        TLSVerify = mkQuadletOption {
          type = bool;
          flag = "--tls-verify";
        };
      };
    };
  };
  config = {
    ref = "${config.name}.artifact";
    serviceName = lib.defaultTo "${config.name}-artifact" config.artifactConfig.ServiceName;
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman artifact ${config.name}";

    finalConfig.Artifact = config.artifactConfig;
  };
}
