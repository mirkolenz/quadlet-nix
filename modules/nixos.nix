{ config, lib, ... }:
let
  cfg = config.virtualisation.quadlet;
  containersStart = 2147483647;
  containersCount = 2147483648;
in
{
  imports = [
    (lib.modules.importApply ./system.nix {
      unitModule = ../units/nixos.nix;
      userManagers = true;
    })
  ];

  # NixOS only, since the userborn of system-manager ignores subordinate IDs.
  options.virtualisation.quadlet.containersUser.enable =
    lib.mkEnableOption ''
      the `containers` user, whose subordinate IDs rootful podman allocates
      for `UserNS=auto`.
      It reserves the upper half of the 32-bit IDs, as podman documents,
      which the automatic ranges of other users never reach''
    // {
      default = true;
    };

  config = lib.mkMerge [
    {
      virtualisation.quadlet.podman = lib.mkDefault config.virtualisation.podman.package;
      virtualisation.podman.enable = lib.mkIf (cfg.enable && cfg.allObjects != [ ]) true;
    }
    (lib.mkIf (cfg.enable && cfg.containersUser.enable) {
      users.users.containers = {
        isSystemUser = true;
        group = "containers";
        # Defaults, so that a configuration declaring this user keeps its
        # own ranges instead of adding ours to them.
        subUidRanges = lib.mkDefault [
          {
            startUid = containersStart;
            count = containersCount;
          }
        ];
        subGidRanges = lib.mkDefault [
          {
            startGid = containersStart;
            count = containersCount;
          }
        ];
      };
      users.groups.containers = { };
    })
  ];
}
