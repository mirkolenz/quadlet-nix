{
  description = "Development inputs for quadlet-nix tests. These do not appear in consumers' lock files.";
  inputs = {
    # quadlet-nix.url = "..";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "";
      # inputs.nixpkgs.follows = "quadlet-nix/nixpkgs";
    };
  };
  outputs = _: { };
}
