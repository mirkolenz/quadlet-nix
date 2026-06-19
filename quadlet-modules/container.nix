{
  lib,
  config,
  lib',
  podman,
  writeShellApplication,
  ...
}:
let
  inherit (lib') mkQuadletOption singleOrList keyValue;
  inherit (lib.types)
    str
    int
    bool
    either
    enum
    ;
in
{
  options = {
    containerConfig = lib'.mkQuadletSectionOption {
      anchor = "container-units-container";
      description = "The systemd container configuration (the `[Container]` section)";
      options = {
        AddCapability = mkQuadletOption {
          type = singleOrList str;
          example = [
            "CAP_DAC_OVERRIDE"
            "CAP_IPC_OWNER"
          ];
        };
        AddDevice = mkQuadletOption {
          type = singleOrList str;
          example = [ "/dev/foo" ];
        };
        AddHost = mkQuadletOption {
          type = singleOrList str;
          flag = "--add-host";
          example = [ "example.com:192.168.10.11" ];
        };
        Annotation = mkQuadletOption {
          type = keyValue;
          example = {
            key = "value";
          };
        };
        AppArmor = mkQuadletOption {
          type = str;
          example = "alternate-profile";
        };
        AutoUpdate = mkQuadletOption {
          type = enum [
            "registry"
            "local"
            "disabled"
          ];
          example = "registry";
        };
        CgroupsMode = mkQuadletOption {
          type = enum [
            "enabled"
            "disabled"
            "no-conmon"
            "split"
          ];
          flag = "--cgroups";
          default = "split";
          example = "no-conmon";
        };
        ContainerName = mkQuadletOption {
          type = str;
          example = "name";
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
        DropCapability = mkQuadletOption {
          type = singleOrList str;
          example = [
            "CAP_DAC_OVERRIDE"
            "CAP_IPC_OWNER"
          ];
        };
        Entrypoint = mkQuadletOption {
          type = str;
          flag = "--entrypoint";
          example = "/foo.sh";
        };
        Environment = mkQuadletOption {
          type = keyValue;
          example = {
            foo = "bar";
          };
        };
        EnvironmentFile = mkQuadletOption {
          type = singleOrList str;
          example = [ "/tmp/env" ];
        };
        EnvironmentHost = mkQuadletOption {
          type = bool;
        };
        Exec = mkQuadletOption {
          type = str;
          example = "/usr/bin/command";
        };
        ExposeHostPort = mkQuadletOption {
          type = singleOrList str;
          flag = "--expose";
          example = [ "50-59" ];
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
        Group = mkQuadletOption {
          type = either int str;
          example = 1234;
        };
        GroupAdd = mkQuadletOption {
          type = singleOrList str;
          flag = "--group-add";
          example = [ "keep-groups" ];
        };
        HealthCmd = mkQuadletOption {
          type = str;
          flag = "--health-cmd";
          example = "/usr/bin/command";
        };
        HealthInterval = mkQuadletOption {
          type = str;
          flag = "--health-interval";
          example = "2m";
        };
        HealthLogDestination = mkQuadletOption {
          type = str;
          flag = "--health-log-destination";
          default = "local";
          example = "/foo/log";
        };
        HealthMaxLogCount = mkQuadletOption {
          type = int;
          flag = "--health-max-log-count";
          default = 5;
        };
        HealthMaxLogSize = mkQuadletOption {
          type = int;
          flag = "--health-max-log-size";
          default = 500;
        };
        HealthOnFailure = mkQuadletOption {
          type = enum [
            "none"
            "kill"
            "restart"
            "stop"
          ];
          flag = "--health-on-failure";
          example = "kill";
        };
        HealthRetries = mkQuadletOption {
          type = int;
          flag = "--health-retries";
          example = 5;
        };
        HealthStartPeriod = mkQuadletOption {
          type = str;
          flag = "--health-start-period";
          example = "1m";
        };
        HealthStartupCmd = mkQuadletOption {
          type = str;
          flag = "--health-startup-cmd";
          example = "command";
        };
        HealthStartupInterval = mkQuadletOption {
          type = str;
          flag = "--health-startup-interval";
          example = "1m";
        };
        HealthStartupRetries = mkQuadletOption {
          type = int;
          flag = "--health-startup-retries";
          example = 8;
        };
        HealthStartupSuccess = mkQuadletOption {
          type = int;
          flag = "--health-startup-success";
          example = 2;
        };
        HealthStartupTimeout = mkQuadletOption {
          type = str;
          flag = "--health-startup-timeout";
          example = "1m33s";
        };
        HealthTimeout = mkQuadletOption {
          type = str;
          flag = "--health-timeout";
          example = "20s";
        };
        HostName = mkQuadletOption {
          type = str;
          flag = "--hostname";
          example = "example.com";
        };
        HttpProxy = mkQuadletOption {
          type = bool;
          flag = "--http-proxy";
          default = true;
        };
        Image = mkQuadletOption {
          type = str;
          example = "ubi8";
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
        Mask = mkQuadletOption {
          type = str;
          example = "/proc/sys/foo:/proc/sys/bar";
        };
        Memory = mkQuadletOption {
          type = str;
          example = "20g";
        };
        Mount = mkQuadletOption {
          type = singleOrList str;
          example = [ "type=tmpfs,tmpfs-size=512M,destination=/tmp" ];
        };
        Network = mkQuadletOption {
          type = singleOrList str;
          example = [ "host" ];
        };
        NetworkAlias = mkQuadletOption {
          type = singleOrList str;
          example = [ "web" ];
        };
        NoNewPrivileges = mkQuadletOption {
          type = bool;
          default = false;
        };
        Notify = mkQuadletOption {
          type = either bool str;
          default = false;
          example = "healthy";
        };
        PidsLimit = mkQuadletOption {
          type = int;
          flag = "--pids-limit";
          example = 10000;
        };
        Pod = mkQuadletOption {
          type = str;
          example = "pod-name.pod";
        };
        PodmanArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--publish 8080:80" ];
        };
        PublishPort = mkQuadletOption {
          type = singleOrList str;
          flag = "--publish";
          example = [
            "8080:80"
            "8443:443"
          ];
        };
        Pull = mkQuadletOption {
          type = str;
          flag = "--pull";
          example = "never";
        };
        ReadOnly = mkQuadletOption {
          type = bool;
          default = false;
        };
        ReadOnlyTmpfs = mkQuadletOption {
          type = bool;
          default = true;
        };
        ReloadCmd = mkQuadletOption {
          type = str;
          example = "/usr/bin/command";
        };
        ReloadSignal = mkQuadletOption {
          type = str;
          example = "SIGHUP";
        };
        Retry = mkQuadletOption {
          type = int;
          flag = "--retry";
          example = 5;
        };
        RetryDelay = mkQuadletOption {
          type = str;
          flag = "--retry-delay";
          example = "5s";
        };
        Rootfs = mkQuadletOption {
          type = str;
          example = "/var/lib/rootfs";
        };
        RunInit = mkQuadletOption {
          type = bool;
          default = false;
        };
        SeccompProfile = mkQuadletOption {
          type = str;
          example = "/tmp/s.json";
        };
        Secret = mkQuadletOption {
          type = singleOrList str;
          example = [ "secret" ];
        };
        SecurityLabelDisable = mkQuadletOption {
          type = bool;
        };
        SecurityLabelFileType = mkQuadletOption {
          type = str;
          example = "usr_t";
        };
        SecurityLabelLevel = mkQuadletOption {
          type = str;
          example = "s0:c1,c2";
        };
        SecurityLabelNested = mkQuadletOption {
          type = bool;
        };
        SecurityLabelType = mkQuadletOption {
          type = str;
          example = "spc_t";
        };
        ServiceName = mkQuadletOption {
          type = str;
          example = "name";
        };
        ShmSize = mkQuadletOption {
          type = str;
          example = "100m";
        };
        StartWithPod = mkQuadletOption {
          type = bool;
          default = true;
        };
        StopSignal = mkQuadletOption {
          type = str;
          flag = "--stop-signal";
          default = "SIGTERM";
          example = "SIGINT";
        };
        StopTimeout = mkQuadletOption {
          type = int;
          flag = "--stop-timeout";
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
        Sysctl = mkQuadletOption {
          type = keyValue;
          example = {
            "net.ipv6.conf.all.disable_ipv6" = 1;
            "net.ipv6.conf.all.use_tempaddr" = 1;
          };
        };
        Timezone = mkQuadletOption {
          type = str;
          example = "local";
        };
        Tmpfs = mkQuadletOption {
          type = singleOrList str;
          example = [ "/work" ];
        };
        UIDMap = mkQuadletOption {
          type = singleOrList str;
          flag = "--uidmap";
          example = [ "0:10000:10" ];
        };
        Ulimit = mkQuadletOption {
          type = singleOrList str;
          example = [ "nofile=1000:10000" ];
        };
        Unmask = mkQuadletOption {
          type = str;
          example = "ALL";
        };
        User = mkQuadletOption {
          type = either int str;
          example = "bin";
        };
        UserNS = mkQuadletOption {
          type = str;
          example = "keep-id:uid=200,gid=210";
        };
        Volume = mkQuadletOption {
          type = singleOrList str;
          example = [ "/source:/dest" ];
        };
        WorkingDir = mkQuadletOption {
          type = str;
          example = "$HOME";
        };
      };
    };
    imageFile = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "The image file to load before starting the service";
    };
    imageStream = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "The image stream to load before starting the service";
    };
  };
  config =
    let
      prestart = writeShellApplication {
        name = "prestart";
        text = ''
          ${lib.optionalString (config.imageFile != null) ''
            ${lib.getExe podman} load -i ${config.imageFile}
          ''}
          ${lib.optionalString (config.imageStream != null) ''
            ${config.imageStream} | ${lib.getExe podman} load
          ''}
        '';
      };
    in
    {
      ref = "${config.name}.container";
      serviceName = lib.defaultTo "${config.name}" config.containerConfig.ServiceName;
      podmanName = lib.defaultTo "systemd-${config.name}" config.containerConfig.ContainerName;
      containerConfig = lib.mkMerge [
        (lib.mkIf (config.imageFile != null) {
          Image = "localhost/${config.imageFile.imageName}:${config.imageFile.imageTag}";
          AutoUpdate = "disabled";
        })
        (lib.mkIf (config.imageStream != null) {
          Image = "localhost/${config.imageStream.imageName}:${config.imageStream.imageTag}";
          AutoUpdate = "disabled";
        })
      ];
      unitConfig = {
        Description = "Podman container ${config.name}";
        StartLimitBurst = lib.mkDefault 3;
        StartLimitIntervalSec = lib.mkDefault 600;
      };
      serviceConfig = {
        Restart = lib.mkDefault "on-failure";
        RestartSec = lib.mkDefault 5;
        TimeoutStartSec = lib.mkDefault 900;
        ExecStartPre = [ (lib.getExe prestart) ];
      };

      finalConfig.Container = config.containerConfig;
    };
}
