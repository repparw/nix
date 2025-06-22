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

  # Helper function to create multiple NixOS system configurations
  mkHost =
    hosts:
    builtins.mapAttrs (
      hostname: system:
      if hostname == "pi" then
        inputs.nixos-raspberrypi.lib.nixosSystem {
          inherit system;
          modules = mkModules hostname ++ [
            {
              imports = with inputs.nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                raspberry-pi-5.display-vc4
                raspberry-pi-5.bluetooth
              ];
            }
            inputs.disko.nixosModules.disko
          ];
          specialArgs = {
            inherit inputs;
            nixos-raspberrypi = inputs.nixos-raspberrypi;
          };
        }
      else
        inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = mkModules hostname;
          specialArgs = {
            inherit inputs;
          };
        }
    ) hosts;
}
