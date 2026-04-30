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
      den._.host-aspects
      den.aspects.shell
      den.aspects.tmux
      den.aspects.git
      den.aspects.ssh
      den.aspects.editors
      den.aspects.file-manager
      den.aspects.scripts
      den.aspects.rclone
    ];

    provides.to-hosts = {
      includes = [ den.aspects.gui ];

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
    };

    user = _: {
      linger = true;
      description = "repparw";
      extraGroups = [
        "adbusers"
        "video"
        "wheel"
      ];
    };

    homeManager = _: {
      xdg.enable = true;
      home.preferXdgDirectories = true;
      services.udiskie = {
        enable = true;
        tray = "never";
        settings.device_config = [
          {
            id_label = "seagate";
            ignore = true;
          }
        ];
      };

    };
  };
}
