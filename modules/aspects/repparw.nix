{ den, inputs, ... }:
{
  flake-file.inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.hosts.x86_64-linux = {
    alpha.users.repparw = { };
    # Disabled while there is no laptop using this host config. Re-enable when
    # beta has hardware again so it participates in flake evals.
    # beta.users.repparw = { };
  };

  den.aspects.repparw = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
      (den.batteries.user-shell "fish")
      den.batteries.host-aspects
      den.aspects.shell
      den.aspects.zellij
      den.aspects.git
      den.aspects.ai
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
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "hm-backup";

            sharedModules = [
              inputs.nixcord.homeModules.default
            ];
          };
        };
    };

    user = _: {
      linger = true;
      description = "repparw";
      extraGroups = [
        "adbusers"
        "gamemode"
        "render"
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
