{ den, inputs, ... }:
{
  flake-file.inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.hosts.x86_64-linux = {
    alpha.users.repparw.aspect = den.aspects.repparw-desktop;
    # Disabled while there is no laptop using this host config. Re-enable when
    # beta has hardware again so it participates in flake evals.
    # beta.users.repparw = { };
  };

  # Headless-safe base account: everything repparw needs on a server.
  # Desktop hosts layer den.aspects.desktop on the host side, which is
  # where the GUI stack and desktop-only AI tooling live.
  den.aspects.repparw = {
    includes = [
      den.batteries.define-user
      den.batteries.primary-user
      (den.batteries.user-shell "fish")
      den.aspects.shell
      den.aspects.tmux
      den.aspects.git
      den.aspects.ssh
      # Base AI tooling; gui AI (dictation/speech) stays desktop-side.
      den.aspects.ai
    ];

    provides.to-hosts.nixos = {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "hm-backup";
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

  # repparw on a desktop host: the base account plus the desktop user
  # layer. Thin by design — the desktop content lives in
  # den.aspects.desktop and follows whichever user it is attached to.
  den.aspects.repparw-desktop = {
    includes = [
      den.aspects.repparw
      den.aspects.desktop
    ];

    user = _: {
      extraGroups = [
        "adbusers"
        "gamemode"
        "render"
        "video"
      ];
    };
  };
}
