{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  lib' = import ../lib.nix lib;
  cfg = config.virtualisation.quadlet;

  duplicateNames = lib.intersectLists (lib.attrNames cfg.containers) (lib.attrNames cfg.pods);
  duplicates =
    key:
    lib.pipe cfg.allObjects [
      (map key)
      (lib.groupBy lib.id)
      (lib.filterAttrs (_: values: lib.length values > 1))
      lib.attrNames
    ];
  duplicateRefs = duplicates (obj: obj.ref);
  duplicateServiceNames = duplicates (obj: obj.serviceName);
  concatObjects = lib.concatMap lib.attrValues [
    cfg.artifacts
    cfg.builds
    cfg.containers
    cfg.images
    cfg.kubes
    cfg.networks
    cfg.pods
    cfg.volumes
  ];
in
{
  options = {
    virtualisation.quadlet = {
      enable = lib.mkEnableOption "quadlet";
      podman = lib.mkOption {
        internal = true;
        type = types.package;
        description = "The podman package the units are generated for";
      };
      package = lib.mkOption {
        type = types.package;
        default = pkgs.callPackage ../pkgs/quadlet.nix { inherit (cfg) podman; };
        defaultText = lib.literalExpression "pkgs.callPackage ./pkgs/quadlet.nix { }";
        description = "The package providing the `quadlet` generator executable";
      };
      autoUpdate = {
        enable = lib.mkEnableOption "quadlet auto update";
        startAt = lib.mkOption {
          type = types.str;
          default = "*-*-* 00:00:00";
          description = "The time to start the auto update";
        };
      };
      quadletctl = {
        enable = lib.mkEnableOption "the `quadletctl` command to manage the units" // {
          default = true;
        };
        package = lib.mkOption {
          type = types.package;
          default = pkgs.callPackage ../pkgs/quadletctl.nix { inherit (cfg) podman; };
          defaultText = lib.literalExpression "pkgs.callPackage ./pkgs/quadletctl.nix { }";
          description = "The package providing the `quadletctl` executable";
        };
        units = lib.mkOption {
          internal = true;
          readOnly = true;
          type = types.lines;
          default = lib.concatMapStrings (
            obj: "${obj.serviceName}\t${obj.kind}\t${obj.podmanName}\t${obj.owner}\n"
          ) cfg.allObjects;
          description = "The table of units that `quadletctl` reads at runtime";
        };
      };
      allObjects = lib.mkOption {
        internal = true;
        readOnly = true;
        default = lib.filter (x: x.enable) concatObjects;
      };
      generatedUnits = lib.mkOption {
        type = types.listOf types.package;
        internal = true;
        default = [ ];
        description = "The packages containing the systemd unit files produced by the podman generator.";
      };
    };
  };
  config = lib.mkIf (cfg.enable && cfg.allObjects != [ ]) {
    assertions = [
      {
        assertion = duplicateNames == [ ];
        message = ''
          The container/pod names should be unique!
          See: ${lib'.quadletDocsUrl}#podname
          The following names are not unique: ${lib.concatStringsSep " " duplicateNames}
        '';
      }
      {
        assertion = duplicateRefs == [ ];
        message = ''
          Quadlet unit file names should be unique.
          The following unit files are not unique: ${lib.concatStringsSep " " duplicateRefs}
        '';
      }
      {
        assertion = duplicateServiceNames == [ ];
        message = ''
          Generated quadlet service names should be unique.
          The following service names are not unique: ${lib.concatStringsSep " " duplicateServiceNames}
        '';
      }
    ]
    ++ (map (obj: {
      assertion = obj.imageFile == null || obj.imageStream == null;
      message = "Only one of imageFile and imageStream can be set for container ${obj.name}";
    }) (lib.attrValues cfg.containers));
  };
}
