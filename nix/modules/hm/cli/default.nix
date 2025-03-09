{
  pkgs,
  stable,
  ...
}:
{
  imports = [
    ./file-manager.nix
    ./nixvim.nix
    ./tmux.nix
    ./zsh.nix
  ];

  xdg.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "$EDITOR";
    YTFZF_ENABLE_FZF_DEFAULT_OPTS = 1;
    ZSH_CACHE_DIR = "$XDG_CACHE_HOME/zsh";
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
      settings.git_protocol = "ssh";
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
        user = {
          email = "ubritos@gmail.com";
          name = "repparw";
        };
        rerere.enabled = true;
        pull.rebase = true;
        maintenance.repo = "/home/repparw/.dotfiles";
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
    with pkgs;
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
      melt # ssh ed25519 keys to seed words
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

      texliveFull
    ]
    ++ (with stable; [
    ]);
}
