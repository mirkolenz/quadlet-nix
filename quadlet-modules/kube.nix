{
  lib',
  config,
  lib,
  ...
}:
let
  inherit (lib') mkQuadletOption singleOrList keyValue;
  inherit (lib.types) str bool enum;
in
{
  options = {
    kubeConfig = lib'.mkQuadletSectionOption {
      anchor = "kube-units-kube";
      description = "The systemd kube configuration (the `[Kube]` section)";
      options = {
        AutoUpdate = mkQuadletOption {
          type = singleOrList str;
          example = [ "registry" ];
        };
        ConfigMap = mkQuadletOption {
          type = singleOrList str;
          example = [ "/tmp/config.map" ];
        };
        ContainersConfModule = mkQuadletOption {
          type = singleOrList str;
          flag = "--module";
          example = [ "/etc/nvd.conf" ];
        };
        ExitCodePropagation = mkQuadletOption {
          type = enum [
            "all"
            "any"
            "none"
          ];
          default = "none";
          example = "all";
        };
        GlobalArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--log-level=debug" ];
        };
        KubeDownForce = mkQuadletOption {
          type = bool;
          flag = "--force";
        };
        LogDriver = mkQuadletOption {
          type = str;
          flag = "--log-driver";
          example = "journald";
        };
        LogOpt = mkQuadletOption {
          type = keyValue;
          flag = "--log-opt";
          example = {
            path = "/var/log/mykube.json";
          };
        };
        Network = mkQuadletOption {
          type = singleOrList str;
          example = [ "host" ];
        };
        PodmanArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--annotation=key=value" ];
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
        SetWorkingDirectory = mkQuadletOption {
          type = enum [
            "yaml"
            "unit"
          ];
          example = "yaml";
        };
        UserNS = mkQuadletOption {
          type = str;
          example = "keep-id:uid=200,gid=210";
        };
        Yaml = mkQuadletOption {
          type = singleOrList str;
          example = [ "/tmp/kube.yaml" ];
        };
      };
    };
  };
  config = {
    ref = "${config.name}.kube";
    serviceName = lib.defaultTo "${config.name}" config.kubeConfig.ServiceName;
    podmanName = "systemd-${config.name}";
    unitConfig = {
      Description = "Podman kube ${config.name}";
      StartLimitBurst = lib.mkDefault 3;
      StartLimitIntervalSec = lib.mkDefault 600;
    };
    serviceConfig = {
      Restart = lib.mkDefault "on-failure";
      RestartSec = lib.mkDefault 5;
      TimeoutStartSec = lib.mkDefault 900;
    };

    finalConfig.Kube = config.kubeConfig;
  };
}
