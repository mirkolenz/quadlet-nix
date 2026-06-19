{ lib, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    let
      # Introspect the option names actually declared by the modules, per section.
      options =
        (lib.evalModules {
          modules = [
            ../config-modules/nixos.nix
            {
              _module.args.pkgs = pkgs;
              _module.check = false;
            }
          ];
        }).options;
      quadlet = options.virtualisation.quadlet;
      sectionKeys =
        attrsOption: section:
        lib.filter (name: !lib.hasPrefix "_" name) (
          builtins.attrNames ((attrsOption.type.getSubOptions [ ]).${section}.type.getSubOptions [ ])
        );
      # Section name (matching Podman's `[Section]`) -> declared option names.
      # The eight unit types follow `Foo` -> `quadlet.foos.fooConfig`; the shared
      # `[Quadlet]` section lives on every object, so any one of them works.
      declared =
        lib.genAttrs
          [
            "Container"
            "Pod"
            "Kube"
            "Network"
            "Volume"
            "Build"
            "Image"
            "Artifact"
          ]
          (
            section:
            let
              name = lib.toLower section;
            in
            sectionKeys quadlet."${name}s" "${name}Config"
          )
        // {
          Quadlet = sectionKeys quadlet.containers "quadletConfig";
        };
      declaredKeys = pkgs.writeText "quadlet-declared-keys.json" (builtins.toJSON declared);
      # Substitute the store paths into the script's `@...@` placeholders.
      script = pkgs.replaceVars ./quadlet-drift.py {
        declaredKeys = "${declaredKeys}";
        quadletGo = "${pkgs.podman.src}/pkg/systemd/quadlet/quadlet.go";
        podmanVersion = pkgs.podman.version;
      };
    in
    {
      packages.quadlet-drift = pkgs.writers.writePython3Bin "quadlet-drift" {
        flakeIgnore = [ "E501" ];
      } script;
      checks = {
        inherit (config.packages) quadlet-drift;
      };
    };
}
