{
  description = "Development inputs for quadlet-nix tests. These do not appear in consumers' lock files.";
  inputs = {
    # quadlet-nix.url = "..";
    # nixpkgs.follows = "quadlet-nix/nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "";
    };
  };
  outputs = _: { };
}
