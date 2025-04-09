{
  description = "repparw's flake";
  inputs = {
    nixvim.url = "github:nix-community/nixvim";
    agenix.url = "github:ryantm/agenix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    home-manager.url = "github:nix-community/home-manager";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nur.url = "github:nix-community/NUR";
  };

  outputs = {...} @ inputs: let
    lib = import ./lib {inherit inputs;};
  in {
    nixosConfigurations =
      lib.mkHost "alpha"
      // lib.mkHost "beta"
      // {
        iso = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [./systems/iso] ++ (lib.mkModules "beta");
          specialArgs = {
            inherit inputs;
          };
        };
      };
  };
}
