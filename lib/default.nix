{inputs, ...}: rec {
  # Import modules from directory - assumes subdirs have default.nix
  importAll = dir: {lib, ...}: {
    imports =
      (lib.filter
        (path:
          lib.strings.hasSuffix ".nix" (toString path)
          && baseNameOf (toString path) != "default.nix")
        (lib.filesystem.listFilesRecursive dir))
      ++ (map
        (name: dir + "/${name}")
        (lib.attrNames (lib.filterAttrs
          (name: type: type == "directory")
          (builtins.readDir dir))));
  };

  # Base modules configuration for all systems
  mkModules = hostname: [
    inputs.nur.modules.nixos.default
    {
      nixpkgs.overlays = builtins.attrValues (import ../overlays {
        inherit inputs;
        outputs = null;
      });
    }
    (importAll ../modules/nixos)
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
            (importAll ../modules/hm)
            ../home/${hostname}.nix
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
