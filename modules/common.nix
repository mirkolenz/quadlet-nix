# `unitModule` adapts every unit to the systemd managers of the importing module.
unitModule:
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

  kinds = [
    "artifact"
    "build"
    "container"
    "image"
    "kube"
    "network"
    "pod"
    "volume"
  ];

  nixImageLoadExe = lib.getExe (pkgs.callPackage ../pkgs/quadlet-load/package.nix { });

  # The `ExecStartPre=` loading a Nix-built image.
  nixImageLoad =
    image:
    lib.escapeShellArgs [
      nixImageLoadExe
      (lib'.nixImageReference image)
      "${image}"
    ];

  mkObjectsOption =
    kind:
    lib.nameValuePair "${kind}s" (
      lib.mkOption {
        type = types.attrsOf (
          types.submodule {
            imports = [
              ../units/${kind}.nix
              ../units/common.nix
              unitModule
            ];
            _module.args = {
              inherit lib' nixImageLoad;
              inherit (cfg) podman images;
            };
          }
        );
        default = { };
        description = "The ${kind}s to manage";
      }
    );

  duplicateNames = lib.intersectLists (lib.attrNames cfg.containers) (lib.attrNames cfg.pods);
  duplicates =
    key:
    lib.pipe cfg.allObjects [
      (lib.groupBy key)
      (lib.filterAttrs (_: values: lib.length values > 1))
      lib.attrNames
    ];
  duplicateRefs = duplicates (obj: obj.ref);
  duplicateServiceNames = duplicates (obj: obj.serviceName);
  concatObjects = lib.concatMap (kind: lib.attrValues cfg."${kind}s") kinds;
in
{
  options = {
    virtualisation.quadlet = lib.listToAttrs (map mkObjectsOption kinds) // {
      enable = lib.mkEnableOption "quadlet";
      podman = lib.mkOption {
        internal = true;
        type = types.package;
        description = "The podman package the units are generated for";
      };
      package = lib.mkOption {
        type = types.package;
        default = pkgs.callPackage ../pkgs/quadlet/package.nix { inherit (cfg) podman; };
        defaultText = lib.literalExpression "pkgs.callPackage ./pkgs/quadlet/package.nix { }";
        description = "The package providing the `quadlet` generator executable";
      };
      autoUpdate = {
        enable = lib.mkEnableOption ''
          the `quadlet-update` timer, which runs the `podman-auto-update` service that Podman ships to update the containers labeled with `AutoUpdate=` and then prune dangling images.
          On NixOS, a user manager runs it only for the owners of rootless units'';
        startAt = lib.mkOption {
          type = types.str;
          default = "*-*-* 00:00:00";
          description = "The `OnCalendar=` schedule of the auto update";
        };
      };
      autoPrune = {
        enable = lib.mkEnableOption ''
          a timer that removes every image that no container uses, such as previous versions and builds.
          Unlike `podman system prune`, it leaves alone the networks of Quadlet units.
          The image of a stopped unit is pulled or loaded again when it starts'';
        startAt = lib.mkOption {
          type = types.str;
          default = "weekly";
          description = "The `OnCalendar=` schedule of the auto prune";
        };
      };
      quadletctl = {
        enable = lib.mkEnableOption "the `quadletctl` command to manage the units" // {
          default = true;
        };
        package = lib.mkOption {
          type = types.package;
          default = pkgs.callPackage ../pkgs/quadletctl/package.nix { inherit (cfg) podman; };
          defaultText = lib.literalExpression "pkgs.callPackage ./pkgs/quadletctl/package.nix { }";
          description = "The package providing the `quadletctl` executable";
        };
        units = lib.mkOption {
          internal = true;
          readOnly = true;
          type = types.lines;
          default = lib.concatMapStrings (
            # An empty field would collapse, since tabs are whitespace for `read`.
            obj: "${obj.serviceName}\t${obj.kind}\t${lib.defaultTo "-" obj.podmanName}\t${obj.owner}\n"
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
    warnings =
      lib.concatMap (
        obj:
        lib.optional (obj.imageFile != null || obj.imageStream != null)
          "virtualisation.quadlet.containers.${obj.name}: `imageFile` and `imageStream` are deprecated. Use `imagePackage` instead."
      ) (lib.attrValues cfg.containers)
      ++ lib.concatMap (
        obj:
        lib.optional (obj.installConfig != { })
          "virtualisation.quadlet: `installConfig` of ${obj.ref} is deprecated. Use `wantedBy`, `requiredBy`, `upheldBy` and `aliases` instead."
      ) cfg.allObjects;
  };
}
