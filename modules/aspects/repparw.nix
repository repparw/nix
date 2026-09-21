{ den, inputs, ... }:
{
  flake-file.inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.repparw = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
      (den.batteries.user-shell "fish")
      den.aspects.shell
      den.aspects.editors
      den.aspects.tmux
      den.aspects.git
      den.aspects.ssh
      den.aspects.secrets
      den.aspects.ai
    ];

    provides.to-hosts =
      { user, ... }:
      {
        nixos =
          { config, ... }:
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
            };

            programs.nh.flake = "${config.home-manager.users.${user.name}.xdg.userDirs.projects}/nix";

            sops.secrets.accessTokens = {
              sopsFile = ../../secrets/nix.sops.yaml;
              mode = "0440";
              owner = user.name;
            };

            nix = {
              settings.allowed-users = [ user.name ];
              extraOptions = ''
                !include ${config.sops.secrets.accessTokens.path}
              '';
            };
          };
      };

    user = _: {
      linger = true;
      description = "repparw";
    };

    homeManager = _: {
      xdg.enable = true;
      home.preferXdgDirectories = true;
    };
  };
}
