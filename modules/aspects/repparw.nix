{ den, inputs, ... }:
{
  flake-file.inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.repparw = {
    includes = [
      den.provides.define-user
      den.provides.primary-user
      (den.provides.user-shell "fish")
      den.aspects.shell
      den.aspects.tmux
      den.aspects.git
      den.aspects.ssh
      den.aspects.editors
      den.aspects.file-manager
      den.aspects.scripts
      den.aspects.rclone
      den.aspects.jellyfin-mpv-shim
    ];

    provides.alpha.includes = [ den.aspects.gui ];
    provides.beta.includes = [ den.aspects.gui ];

    nixos =
      { ... }:
      {
        imports = [ inputs.home-manager.nixosModules.home-manager ];

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "hm-backup";
        };
      };

    user =
      { ... }:
      {
        linger = true;
        description = "repparw";
        extraGroups = [
          "adbusers"
          "wheel"
        ];
      };

    homeManager =
      { ... }:
      {
        xdg.enable = true;
        home.preferXdgDirectories = true;
        services.udiskie = {
          enable = true;
          tray = "never";
        };
      };
  };
}
