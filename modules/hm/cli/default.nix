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

    zoxide = {
      enable = true;
      options = [ "--cmd=cd" ];
    };

    eza = {
      enable = true;
      extraOptions = [ "--icons" ];
    };

    git = {
      enable = true;
      userEmail = "ubritos@gmail.com";
      userName = "repparw";

      extraConfig = {
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
        merge.conflictdiff = "diff3";
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

  home.packages =
    let
      nvim = pkgs.neovim.extend config.lib.stylix.nixvim.config;
    in
    with pkgs;
    [
      # essentials
      nvim
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

      qmk

      # CLI tools
      playerctl
      libqalculate

      fastfetch
      tlrc # tldr

      pdfgrep
      catdoc # provides catppt and xls2csv

      # Modern replacements of basic tools
      tree

      manix
    ]
    ++ (with pkgs.stable; [
    ]);
}
