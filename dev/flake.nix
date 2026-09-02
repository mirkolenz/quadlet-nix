{
  description = "Development inputs for quadlet-nix. These do not appear in consumers' lock files.";
  inputs = {
    # quadlet-nix.url = "..";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "";
      # inputs.nixpkgs.follows = "quadlet-nix/nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "";
    };
  };
  outputs = _: { };
}
