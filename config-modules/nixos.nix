{ inputs, ... }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  nixosUtils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" { inherit lib config pkgs; };
  systemdUtils = nixosUtils.systemdUtils;

  cfg = config.virtualisation.quadlet;
  podman = config.virtualisation.podman.package or pkgs.podman;
  lib' = inputs.self.lib {
    inherit lib systemdUtils;
  };

  mkSubmodule =
    path:
    types.submodule {
      imports = [
        path
        ../quadlet-modules/common.nix
        ../quadlet-modules/uid.nix
      ];
      _module.args = {
        inherit lib' podman;
        inherit (pkgs) writeShellApplication;
      };
    };

  allObjects = lib.concatMap lib.attrValues [
    cfg.containers
    cfg.networks
  ];

  rootfulObjects = lib.filter (obj: obj.uid == null) allObjects;
  rootlessObjects = lib.filter (obj: obj.uid != null) allObjects;
  rootlessUsers = lib.unique (map (obj: obj.uid) rootlessObjects);

  duplicateNames = lib.intersectLists (lib.attrNames cfg.containers) (lib.attrNames cfg.pods);

  mkAutoUpdate =
    autoStartTarget:
    import ./update.nix {
      inherit lib podman autoStartTarget;
      inherit (cfg.autoUpdate) startAt;
    };

  mkUnitOverride =
    obj:
    lib.nameValuePair obj.serviceName {
      overrideStrategy = "asDropin";
      text = lib'.mkUnitText {
        Unit.X-QuadletNixHash = builtins.hashString "sha256" obj.text;
      };
    };

  mkQuadletName =
    obj:
    if obj.uid == null then "containers/systemd/${obj.ref}" else "containers/systemd/users/${obj.ref}";

  mkSystemdName =
    obj:
    if obj.uid == null then
      "etc/systemd/system/${obj.serviceName}.service"
    else
      "etc/systemd/user/${obj.serviceName}.service";

  mkSystemdPath =
    obj:
    if obj.uid == null then
      "/run/systemd/generator/${obj.serviceName}.service"
    else
      "/run/user/${toString obj.uid}/systemd/generator/${obj.serviceName}.service";
in
{
  options = {
    virtualisation.quadlet = {
      enable = lib.mkEnableOption "quadlet";
      autoUpdate = {
        enable = lib.mkOption {
          type = types.bool;
          default = true;
        };
        startAt = lib.mkOption {
          type = types.str;
          default = "*-*-* 00:00:00";
        };
      };
      containers = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/container.nix);
        default = { };
      };
      networks = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/network.nix);
        default = { };
      };
      pods = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/pod.nix);
        default = { };
      };
      kubes = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/kube.nix);
        default = { };
      };
      volumes = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/volume.nix);
        default = { };
      };
      builds = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/build.nix);
        default = { };
      };
      images = lib.mkOption {
        type = types.attrsOf (mkSubmodule ../quadlet-modules/image.nix);
        default = { };
      };
    };
  };

  config = lib.mkIf (cfg.enable && lib.length allObjects > 0) {
    assertions =
      [
        {
          assertion = duplicateNames == [ ];
          message = ''
            The container/pod names should be unique!
            See: https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html#podname
            The following names are not unique: ${lib.concatStringsSep " " duplicateNames}
          '';
        }
      ]
      ++ (map (obj: {
        assertion = obj.imageFile == null || obj.imageStream == null;
        message = "Only one of imageFile and imageStream can be set for container ${obj.name}";
      }) (lib.attrValues cfg.containers));
    virtualisation.podman.enable = true;
    environment.etc = lib.listToAttrs (
      map (
        obj:
        lib.nameValuePair (mkQuadletName obj) {
          inherit (obj) text;
        }
      ) allObjects
    );
    # The symlinks are not necessary for the services to be honored by systemd,
    # but necessary for NixOS activation process to pick them up for updates.
    systemd.packages = lib.singleton (
      pkgs.linkFarm "quadlet-nix" (
        map (obj: {
          name = mkSystemdName obj;
          path = mkSystemdPath obj;
        }) allObjects
      )
    );
    # Inject X-RestartIfChanged=${hash} for NixOS to detect changes.
    systemd.units = lib.listToAttrs (map mkUnitOverride rootfulObjects);
    systemd.user.units = lib.listToAttrs (map mkUnitOverride rootlessObjects);

    systemd.services.quadlet-auto-update = lib.mkIf (
      cfg.autoUpdate.enable && lib.length rootfulObjects > 0
    ) (mkAutoUpdate "multi-user.target");
    systemd.user.services.quadlet-auto-update =
      lib.mkIf (cfg.autoUpdate.enable && lib.length rootlessObjects > 0)
        (
          lib.recursiveUpdate (mkAutoUpdate "default.target") {
            unitConfig.ConditionUser = lib.concatMapStringsSep "|" toString rootlessUsers;
          }
        );
  };
}
