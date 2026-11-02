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
          let
            xdg = config.home-manager.users.${user.name}.xdg;
          in
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
            };

            # Propagate XDG env vars to all processes (SSH, nix-shell, agents)
            # that do not source home-manager's hm-session-vars.sh. Paths come
            # from home-manager's own xdg module to avoid hardcoding.
            environment.variables = {
              NPM_CONFIG_CACHE = "${xdg.cacheHome}/npm";
              NPM_CONFIG_USERCONFIG = "${xdg.configHome}/npm/npmrc";
              ANDROID_USER_HOME = "${xdg.dataHome}/android";
              CARGO_HOME = "${xdg.dataHome}/cargo";
              CLAUDE_CONFIG_DIR = "${xdg.configHome}/claude";
              OCI_CLI_CONFIG_FILE = "${xdg.configHome}/oci/config";
              PULSE_COOKIE = "${xdg.configHome}/pulse/cookie";
              GOPATH = "${xdg.dataHome}/go";
              GOBIN = "${xdg.dataHome}/go/bin";
              WGETRC = "${xdg.configHome}/wget/wgetrc";
              HISTFILE = "${xdg.stateHome}/bash/history";
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
