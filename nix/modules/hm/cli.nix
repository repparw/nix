{ pkgs, unstable, ... }:

{
  programs = {
    git = {
      enable = true;
      userEmail = "ubritos@gmail.com";
      userName = "repparw";
      extraConfig = {
        rerere.enabled = true;
        pull.rebase = true;
      };
    };
  };

  programs.ssh.addKeysToAgent = "yes";

  home.packages = with pkgs; [
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
    tmux
    less
    base16-schemes
    yt-dlp
    fzf
    ytfzf

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

    lf
    vimv-rs # bulk rename
    pdfgrep
    catdoc # provides catppt and xls2csv

    tig

    # Modern replacements of basic tools
    unstable.bottom
    bat
    colordiff
    duf
    du-dust
    fd
    ripgrep
    zoxide
    eza
    tree

    manix

    nodejs # remove after porting nvim plugins to nix cfg
  ];

  programs.neovim = {
    enable = true;
    package = unstable.neovim-unwrapped;
    extraPackages =
      (with pkgs; [
        beautysh

        marksman

        lua-language-server
        stylua

        nil # nix lsp
        nixfmt-rfc-style

        nodePackages_latest.typescript-language-server

        biome
        nodePackages.prettier

        rust-analyzer

        ruby-lsp
        rufo
      ])
      ++ (with unstable; [
        basedpyright
        vue-language-server

        vimPlugins.avante-nvim
      ]);
  };
}
