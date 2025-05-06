{
  description = "repparw's flake";
  inputs = {
    agenix.url = "github:ryantm/agenix";
    home-manager.url = "github:nix-community/home-manager";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixvim-config.url = "github:repparw/nixvim-config";
    nur.url = "github:nix-community/NUR";
    stylix.url = "github:danth/stylix";
  };

  outputs = inputs: let
    lib = import ./lib {inherit inputs;};
  in {
    nixosConfigurations =
      lib.mkHost "alpha" "x86_64-linux"
      // lib.mkHost "beta" "x86_64-linux"
      // lib.mkHost "pi" "aarch64-linux"
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
