{inputs, ...}: rec {
  # Base modules configuration for all systems
  mkModules = hostname: [
    # Adds the NUR overlay
    inputs.nur.modules.nixos.default
    # NUR modules to import
    ../modules/nixos
    ../systems/common.nix
    ../systems/${hostname}
    inputs.nix-index-database.nixosModules.nix-index
    inputs.agenix.nixosModules.default
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "hm-backup";
        extraSpecialArgs = {
          inherit inputs;
        };
        users.repparw = {
          imports = [
            ../modules/hm
            ../home/common
            ../home/${hostname}
            inputs.nixvim.homeManagerModules.nixvim
          ];
        };
      };
    }
  ];

  # Helper function to create a NixOS system configuration
  mkHost = hostname: {
    ${hostname} = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = mkModules hostname;
      specialArgs = {
        inherit inputs;
      };
    };
  };
}
