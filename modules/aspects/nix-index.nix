{ inputs, ... }:
{
  flake-file.inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.nix-index = {
    nixos =
      { ... }:
      {
        imports = [ inputs.nix-index-database.nixosModules.nix-index ];

        programs.nix-index-database.comma.enable = true;
      };
  };
}
