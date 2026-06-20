{
  config,
  lib',
  podman,
  lib,
  ...
}:
let
  inherit (lib') mkQuadletOption singleOrList keyValue;
  inherit (lib.types) str bool enum;
in
{
  options = {
    networkConfig = lib'.mkQuadletSectionOption {
      anchor = "network-units-network";
      description = "The systemd network configuration (the `[Network]` section)";
      options = {
        ContainersConfModule = mkQuadletOption {
          type = singleOrList str;
          flag = "--module";
          example = [ "/etc/nvd.conf" ];
        };
        DisableDNS = mkQuadletOption {
          type = bool;
          flag = "--disable-dns";
          default = false;
        };
        DNS = mkQuadletOption {
          type = singleOrList str;
          example = [ "192.168.55.1" ];
        };
        Driver = mkQuadletOption {
          type = enum [
            "bridge"
            "macvlan"
            "ipvlan"
          ];
          flag = "--driver";
          default = "bridge";
        };
        Gateway = mkQuadletOption {
          type = singleOrList str;
          flag = "--gateway";
          example = [ "192.168.55.3" ];
        };
        GlobalArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--log-level=debug" ];
        };
        InterfaceName = mkQuadletOption {
          type = str;
          flag = "--interface-name";
          example = "enp1";
        };
        Internal = mkQuadletOption {
          type = bool;
          flag = "--internal";
          default = false;
        };
        IPAMDriver = mkQuadletOption {
          type = enum [
            "host-local"
            "dhcp"
            "none"
          ];
          flag = "--ipam-driver";
          example = "dhcp";
        };
        IPRange = mkQuadletOption {
          type = singleOrList str;
          flag = "--ip-range";
          example = [ "192.168.55.128/25" ];
        };
        IPv6 = mkQuadletOption {
          type = bool;
          flag = "--ipv6";
        };
        Label = mkQuadletOption {
          type = keyValue;
          example = {
            key = "value";
          };
        };
        NetworkDeleteOnStop = mkQuadletOption {
          type = bool;
          default = false;
        };
        NetworkName = mkQuadletOption {
          type = str;
          example = "foo";
        };
        Options = mkQuadletOption {
          type = keyValue;
          flag = "--opt";
          example = {
            isolate = "true";
          };
        };
        PodmanArgs = mkQuadletOption {
          type = singleOrList str;
          example = [ "--dns=192.168.55.1" ];
        };
        ServiceName = mkQuadletOption {
          type = str;
          example = "name";
        };
        Subnet = mkQuadletOption {
          type = singleOrList str;
          flag = "--subnet";
          example = [ "192.5.0.0/16" ];
        };
      };
    };
  };
  config = {
    ref = "${config.name}.network";
    serviceName = lib.defaultTo "${config.name}-network" config.networkConfig.ServiceName;
    podmanName = lib.defaultTo "systemd-${config.name}" config.networkConfig.NetworkName;
    unitConfig.Description = "Podman network ${config.name}";
    serviceConfig = lib.mkIf (lib.versionOlder podman.version "5.5") {
      ExecStopPost = "${lib.getExe podman} network rm ${config.podmanName}";
    };
    networkConfig = lib.mkIf (lib.versionAtLeast podman.version "5.5") {
      NetworkDeleteOnStop = true;
    };

    finalConfig.Network = config.networkConfig;
  };
}
