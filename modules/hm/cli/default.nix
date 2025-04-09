{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./file-manager.nix
    ./nixvim
    ./scripts.nix
    ./tmux.nix
    ./zsh.nix
  ];

  xdg.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "$EDITOR";
    YTFZF_ENABLE_FZF_DEFAULT_OPTS = 1;
    ZSH_CACHE_DIR = "${config.xdg.cacheHome}/zsh";
    XDG_SCREENSHOTS_DIR = "${config.xdg.userDirs.pictures}/ss";
    XCURSOR_SIZE = 24;
    HYPRCURSOR_SIZE = 24;
  };

  programs = {
    fd = {
      enable = true;
      hidden = true;
    };

    fzf = {
      enable = true;
      defaultOptions = [
        "--no-mouse"
        "--multi"
        "--select-1"
        "--reverse"
        "--height 50%"
        "--inline-info"
        "--scheme=history"
      ];
      defaultCommand = "fd --type f --hidden --follow --exclude .git";
    };

    gh = {
      enable = true;
      extensions = [pkgs.gh-copilot];
      settings.git_protocol = "ssh";
    };

    zoxide = {
      enable = true;
      options = ["--cmd=cd"];
    };

    eza = {
      enable = true;
      extraOptions = ["--icons"];
    };

    git = {
      enable = true;
      userEmail = "ubritos@gmail.com";
      userName = "repparw";
      extraConfig = {
        user = {
          email = "ubritos@gmail.com";
          name = "repparw";
        };
        column.ui = "auto";
        branch.sort = "-commiterdate";
        tag.sort = "version:refname";
        init.defaultBranch = "main";
        diff = {
          algorithm = "histogram";
          colorMoved = "plain";
          mnemonicPrefix = true;
          renames = true;
        };
        push = {
          default = simple;
          autoSetupRemote = true;
        };
        rerere = {
          enabled = true;
          autoupdate = true;
        };
        pull.rebase = true;
        maintenance.repo = "/home/repparw/nix";
        rebase = {
          autoSquash = true;
          autoStash = true;
          updateRefs = true;
        };
      };
      # TODO merge diff3, mergetool, more git config options, aliases?
    };

    ssh = {
      enable = true;
      addKeysToAgent = "yes";

      matchBlocks = {
        rpi = {
          hostname = "home.repparw.me";
          port = 2222;
          user = "dietpi";
        };
      };
    };
  };

  home.packages = with pkgs;
    [
      # essentials
      zsh
      curl
      wget
      unzip
      bluez
      jq
      tree
      ffmpeg
      imagemagick
      less
      base16-schemes
      yt-dlp
      fzf
      ytfzf

      qmk

      # CLI tools
      playerctl
      rclone
      ueberzugpp
      libqalculate

      fastfetch
      axel
      tlrc # tldr
      nq # Command queue

      pdfgrep
      catdoc # provides catppt and xls2csv

      tig

      # Modern replacements of basic tools
      bottom
      bat
      colordiff
      duf
      du-dust
      ripgrep
      tree

      manix
      comma

      texliveFull
    ]
    ++ (with pkgs.stable; [
      ]);
}
