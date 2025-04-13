{inputs, ...}: rec {
  # Base modules configuration for all systems
  mkModules = hostname: [
    # Adds the NUR overlay
    inputs.nur.modules.nixos.default
    # Apply overlays
    {
      nixpkgs.overlays = builtins.attrValues (import ../overlays {
        inherit inputs;
        outputs = null;
      });
    }
    # NUR modules to import
    ../modules/nixos
    ../systems/${hostname}
    inputs.nix-index-database.nixosModules.nix-index
    ../secrets/nixos.nix
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
            ../home/${hostname}
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
