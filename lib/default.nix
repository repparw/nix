{ inputs, ... }:
rec {
  # Base modules configuration for all systems
  mkModules = hostname: [
    # Adds the NUR overlay
    inputs.nur.modules.nixos.default
    # Apply overlays
    {
      nixpkgs.overlays = builtins.attrValues (
        import ../overlays {
          inherit inputs;
          outputs = null;
        }
      );
    }
    # NUR modules to import
    ../modules/nixos
    ../systems/${hostname}
    inputs.nix-index-database.nixosModules.nix-index
    { programs.nix-index-database.comma.enable = true; }
    ../secrets/nixos.nix
    inputs.home-manager.nixosModules.home-manager
    inputs.stylix.nixosModules.stylix

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
            ../home/${hostname}.nix
          ];
        };
      };
    }
  ];

  # Helper function to create a NixOS system with additional modules based on hostname
  mkSystem = hostname: system: extraModules:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = mkModules hostname ++ extraModules;
      specialArgs = {
        inherit inputs;
      };
    };

  # Helper function to create multiple NixOS system configurations
  mkHost = hosts:
    let
      # Define extra modules based on hostname patterns
      getExtraModules = hostname:
        if hostname == "pi" then [
          inputs.disko.nixosModules.disko
          inputs.nixos-hardware.nixosModules.raspberry-pi-5
        ]
        else if hostname == "delta" then [
          inputs.jovian.nixosModules.default
        ]
        else [];
    in
    builtins.mapAttrs (
      hostname: system:
      mkSystem hostname system (getExtraModules hostname)
    ) hosts;
}
