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

      maintenance = {
        enable = true;
        repositories = ["/home/repparw/nix"];
      };

      extraConfig = {
        # git maintainer standards until git3?
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
          default = "simple";
          autoSetupRemote = true;
          followTags = true;
        };
        fetch = {
          prune = true;
          pruneTags = true;
          all = true;
        };
        # why not?
        rerere = {
          enabled = true;
          autoupdate = true;
        };
        pull.rebase = true;
        rebase = {
          autoSquash = true;
          autoStash = true;
          updateRefs = true;
        };
      };
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
      yt-dlp
      fzf
      ytfzf

      qmk

      # CLI tools
      playerctl
      rclone
      libqalculate

      fastfetch
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
