{
  config,
  lib',
  lib,
  ...
}:
let
  inherit (lib') mkQuadletOption singleOrList keyValue;
  inherit (lib.types) str int bool;
in
{
  options = {
    buildConfig = lib'.mkQuadletSectionOption {
      anchor = "build-units-build";
      description = "The systemd build configuration (the `[Build]` section)";
      options = {
        Annotation = mkQuadletOption {
          type = keyValue;
          flag = "--annotation";
          example = {
            annotation = "value";
          };
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
        BuildArg = mkQuadletOption {
          type = keyValue;
          flag = "--build-arg";
          example = {
            foo = "bar";
          };
        };
        ContainersConfModule = mkQuadletOption {
          type = singleOrList str;
          flag = "--module";
          example = [ "/etc/nvd.conf" ];
        };
        DNS = mkQuadletOption {
          type = singleOrList str;
          flag = "--dns";
          example = [ "192.168.55.1" ];
        };
        DNSOption = mkQuadletOption {
          type = singleOrList str;
          flag = "--dns-option";
          example = [ "ndots:1" ];
        };
        DNSSearch = mkQuadletOption {
          type = singleOrList str;
          flag = "--dns-search";
          example = [ "example.com" ];
        };
        Environment = mkQuadletOption {
          type = keyValue;
          example = {
            foo = "bar";
          };
        };
        File = mkQuadletOption {
          type = str;
          flag = "--file";
          example = "/path/to/Containerfile";
        };
        ForceRM = mkQuadletOption {
          type = bool;
          flag = "--force-rm";
          default = true;
        };
        GlobalArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--log-level=debug" ];
        };
        GroupAdd = mkQuadletOption {
          type = singleOrList str;
          flag = "--group-add";
          example = [ "keep-groups" ];
        };
        IgnoreFile = mkQuadletOption {
          type = str;
          flag = "--ignorefile";
          example = "/path/to/.customignore";
        };
        ImageTag = mkQuadletOption {
          type = singleOrList str;
          flag = "--tag";
          example = [ "localhost/imagename" ];
        };
        Label = mkQuadletOption {
          type = keyValue;
          flag = "--label";
          example = {
            key = "value";
          };
        };
        Network = mkQuadletOption {
          type = singleOrList str;
          example = [ "host" ];
        };
        PodmanArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--pull never" ];
        };
        Pull = mkQuadletOption {
          type = str;
          flag = "--pull";
          example = "never";
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
        Secret = mkQuadletOption {
          type = singleOrList str;
          example = [ "id=mysecret,src=path" ];
        };
        ServiceName = mkQuadletOption {
          type = str;
          example = "name";
        };
        SetWorkingDirectory = mkQuadletOption {
          type = str;
          example = "unit";
        };
        Target = mkQuadletOption {
          type = str;
          flag = "--target";
          example = "my-app";
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
        Volume = mkQuadletOption {
          type = singleOrList str;
          example = [ "/source:/dest" ];
        };
      };
    };
  };
  config = {
    ref = "${config.name}.build";
    serviceName = lib.defaultTo "${config.name}-build" config.buildConfig.ServiceName;
    podmanName = "systemd-${config.name}";
    unitConfig.Description = "Podman build ${config.name}";

    finalConfig.Build = config.buildConfig;
  };
}
