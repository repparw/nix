{
  pkgs,
  config,
  ...
}:
{
  imports = [
    ./file-manager.nix
    ./rclone.nix
    ./scripts.nix
    ./tmux.nix
    ./shell.nix
  ];

  xdg.enable = true;

  home.sessionVariables = {
    MANPAGER = "nvim +Man!";
    EDITOR = "nvim";
    VISUAL = "$EDITOR";
  };

  programs = {
    eza = {
      enable = true;
      extraOptions = [ "--icons" ];
    };

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
      extensions = [ pkgs.gh-copilot ];
    };

    git = {
      enable = true;

      settings = {
        user = {
          email = "ubritos@gmail.com";
          name = "repparw";
        };
        url = {
          "git@github.com:repparw/" = {
            insteadOf = "repparw:";
          };
          "git@github.com:" = {
            insteadOf = "gh:";
          };
        };

        # git maintainer standards until git3?
        column.ui = "auto";
        branch.sort = "-committerdate";
        tag.sort = "version:refname";
        init.defaultBranch = "main";
        diff = {
          algorithm = "histogram";
          colorMoved = "plain";
          mnemonicPrefix = true;
          renames = true;
        };
        merge.conflictstyle = "zdiff3";
        push = {
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

    opencode.enable = true;

    ssh = {
      enable = true;
      enableDefaultConfig = false;

      matchBlocks = {
        alpha = {
          port = 10000;
          user = "repparw";
        };
        beta = {
          hostname = "home.repparw.me";
          port = 10000;
          user = "repparw";
        };
        pi = {
          hostname = "home.repparw.me";
          port = 22;
          user = "repparw";
        };
      };
    };

    zoxide = {
      enable = true;
      options = [ "--cmd=cd" ];
    };

  };

  home.packages =
    let
      nvim = pkgs.neovim.extend config.stylix.targets.nixvim.exportedModule;
    in
    with pkgs;
    [
      # essentials
      nvim
      devenv
      curl
      wget
      jq

      android-tools
      unzip
      rmtrash
      tree
      ffmpeg
      imagemagick
      less
      yt-dlp

      # CLI tools
      playerctl
      libqalculate

      fastfetch
      tlrc # tldr

      pdfgrep
      catdoc # provides catppt and xls2csv

      gemini-cli
    ]
    ++ (with pkgs.stable; [
    ]);
}
