{ den, inputs, ... }:
{
  flake-file.inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.hosts.x86_64-linux = {
    alpha.users.repparw = { };
    beta.users.repparw = { };
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
        initialHashedPassword = "$y$j9T$WPuWlgd7OQOePD8XKqNVv0$Pe9XhFT2hKh1YnyDVHxEwOe.IYTMr8K4JUtxBVjEza/";
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
