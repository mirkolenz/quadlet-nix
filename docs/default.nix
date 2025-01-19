{ ... }:
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages = {
        optionsMarkdown = pkgs.callPackage ./options.nix { };
        book = pkgs.callPackage ./book.nix {
          inherit (config.packages) optionsMarkdown;
        };
        docs = config.packages.book;
      };
    };
}
