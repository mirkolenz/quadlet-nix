{
  lib',
  config,
  lib,
  ...
}:
let
  inherit (lib') mkQuadletOption singleOrList keyValue;
  inherit (lib.types) str int enum;
in
{
  options = {
    podConfig = lib'.mkQuadletSectionOption {
      anchor = "pod-units-pod";
      description = "The systemd pod configuration (the `[Pod]` section)";
      options = {
        AddHost = mkQuadletOption {
          type = singleOrList str;
          flag = "--add-host";
          example = [ "example.com:192.168.10.11" ];
        };
        ContainersConfModule = mkQuadletOption {
          type = singleOrList str;
          flag = "--module";
          example = [ "/etc/nvd.conf" ];
        };
        DNS = mkQuadletOption {
          type = singleOrList str;
          example = [ "192.168.55.1" ];
        };
        DNSOption = mkQuadletOption {
          type = singleOrList str;
          example = [ "ndots:1" ];
        };
        DNSSearch = mkQuadletOption {
          type = singleOrList str;
          example = [ "example.com" ];
        };
        ExitPolicy = mkQuadletOption {
          type = enum [
            "continue"
            "stop"
          ];
          default = "stop";
        };
        GIDMap = mkQuadletOption {
          type = singleOrList str;
          flag = "--gidmap";
          example = [ "0:10000:10" ];
        };
        GlobalArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--log-level=debug" ];
        };
        HostName = mkQuadletOption {
          type = str;
          flag = "--hostname";
          example = "name";
        };
        IP = mkQuadletOption {
          type = str;
          flag = "--ip";
          example = "192.5.0.1";
        };
        IP6 = mkQuadletOption {
          type = str;
          flag = "--ip6";
          example = "2001:db8::1";
        };
        Label = mkQuadletOption {
          type = keyValue;
          example = {
            key = "value";
          };
        };
        Network = mkQuadletOption {
          type = singleOrList str;
          example = [ "host" ];
        };
        NetworkAlias = mkQuadletOption {
          type = singleOrList str;
          example = [ "name" ];
        };
        PodmanArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--cpus=2" ];
        };
        PodName = mkQuadletOption {
          type = str;
          example = "name";
        };
        PublishPort = mkQuadletOption {
          type = singleOrList str;
          flag = "--publish";
          example = [ "8080:80" ];
        };
        ServiceName = mkQuadletOption {
          type = str;
          example = "name";
        };
        ShmSize = mkQuadletOption {
          type = str;
          example = "100m";
        };
        StopTimeout = mkQuadletOption {
          type = int;
          example = 20;
        };
        SubGIDMap = mkQuadletOption {
          type = str;
          flag = "--subgidname";
          example = "gtest";
        };
        SubUIDMap = mkQuadletOption {
          type = str;
          flag = "--subuidname";
          example = "utest";
        };
        UIDMap = mkQuadletOption {
          type = singleOrList str;
          flag = "--uidmap";
          example = [ "0:10000:10" ];
        };
        UserNS = mkQuadletOption {
          type = str;
          example = "keep-id:uid=200,gid=210";
        };
        Volume = mkQuadletOption {
          type = singleOrList str;
          example = [ "/source:/dest" ];
        };
      };
    };
  };
  config = {
    ref = "${config.name}.pod";
    serviceName = lib.defaultTo "${config.name}-pod" config.podConfig.ServiceName;
    podmanName = lib.defaultTo "systemd-${config.name}" config.podConfig.PodName;
    unitConfig = {
      Description = "Podman pod ${config.name}";
      StartLimitBurst = lib.mkDefault 3;
      StartLimitIntervalSec = lib.mkDefault 600;
    };
    serviceConfig = {
      Restart = lib.mkDefault "on-failure";
      RestartSec = lib.mkDefault 5;
      TimeoutStartSec = lib.mkDefault 900;
    };

    finalConfig.Pod = config.podConfig;
  };
}
