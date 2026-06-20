{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      evalModule =
        module:
        (lib.evalModules {
          modules = [
            module
            {
              _module.args = { inherit pkgs; };
              _module.check = false;
            }
          ];
        }).options;
      mkOptions =
        options:
        (pkgs.nixosOptionsDoc {
          inherit options;
          transformOptions =
            opt:
            let
              # hide /nix/store/* prefix
              opt' = opt // {
                declarations = [ ];
              };
            in
            # drop the uninformative `Default: null` rendered for unset keys,
            # while keeping any Podman default documented via `defaultText`
            if (opt'.default.text or null) == "null" then removeAttrs opt' [ "default" ] else opt';
        }).optionsCommonMark;
      subpages = [
        "containers"
        "networks"
        "pods"
        "kubes"
        "volumes"
        "builds"
        "images"
        "artifacts"
      ];
      mkSection =
        {
          prefix,
          title,
          module,
        }:
        let
          options = evalModule module;
        in
        {
          inherit prefix title;
          pages = [
            {
              name = "core";
              title = "Core";
              value = mkOptions (lib.removeAttrs options.virtualisation.quadlet subpages);
            }
          ]
          ++ map (subpage: {
            name = subpage;
            title = lib.toSentenceCase subpage;
            value = mkOptions options.virtualisation.quadlet.${subpage};
          }) subpages;
        };
      sections = [
        (mkSection {
          prefix = "nixos";
          title = "NixOS";
          module = ../modules/nixos.nix;
        })
        (mkSection {
          prefix = "home-manager";
          title = "Home Manager";
          module = ../modules/hm.nix;
        })
      ];
    in
    {
      packages.docs = pkgs.callPackage ./book.nix { inherit sections; };
    };
}
