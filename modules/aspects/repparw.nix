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
      den.aspects.git-updater
      den.aspects.ssh
      den.aspects.secrets
      den.aspects.ai
      den.aspects.xdg
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

            # Propagate XDG env vars to all processes (SSH, nix-shell, agents)
            # that do not source home-manager's hm-session-vars.sh.
            environment.variables = {
              NPM_CONFIG_CACHE = "/home/repparw/.cache/npm";
              NPM_CONFIG_USERCONFIG = "/home/repparw/.config/npm/npmrc";
              ANDROID_USER_HOME = "/home/repparw/.local/share/android";
              CARGO_HOME = "/home/repparw/.local/share/cargo";
              CLAUDE_CONFIG_DIR = "/home/repparw/.config/claude";
              OCI_CLI_CONFIG_FILE = "/home/repparw/.config/oci/config";
              PULSE_COOKIE = "/home/repparw/.config/pulse/cookie";
              GOPATH = "/home/repparw/.local/share/go";
              GOBIN = "/home/repparw/.local/share/go/bin";
              WGETRC = "/home/repparw/.config/wget/wgetrc";
              HISTFILE = "/home/repparw/.local/state/bash/history";
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
