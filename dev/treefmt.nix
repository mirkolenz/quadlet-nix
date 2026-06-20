{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];
  perSystem =
    { ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";
        settings.excludes = [ "CHANGELOG.md" ];
        programs = {
          # keep-sorted start
          keep-sorted.enable = true;
          nixf-diagnose.enable = true;
          nixfmt.enable = true;
          oxfmt.enable = true;
          ruff-check.enable = true;
          ruff-format.enable = true;
          # keep-sorted end
        };
      };
    };
}
