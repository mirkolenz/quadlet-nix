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
          # hide /nix/store/* prefix
          transformOptions = opt: opt // { declarations = [ ]; };
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
        { prefix, title, module }:
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
          module = ../config-modules/nixos.nix;
        })
        (mkSection {
          prefix = "home-manager";
          title = "Home Manager";
          module = ../config-modules/hm.nix;
        })
      ];
    in
    {
      packages.docs = pkgs.callPackage ./book.nix { inherit sections; };
    };
}
