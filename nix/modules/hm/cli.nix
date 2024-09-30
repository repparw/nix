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

  programs.tmux = {
      enable = true;
    shell = "${pkgs.zsh}/bin/zsh";
    terminal = "xterm-kitty";
    historyLimit = 10000;
	prefix = "C-a";
	mouse = true;
	baseIndex = 1;
    plugins = with pkgs.tmuxPlugins;
      [
	  sensible
	  pain-control
	  #power-zoom
	  #tmux-floax TODO
	  vim-tmux-navigator
	  yank
	  resurrect
	  continuum

	  gruvbox
      ];
    extraConfig = ''
		bind-key @ command-prompt -p "create pane from:" "join-pane -s ':%%'"

		set-option -g update-environment "DISPLAY WAYLAND_DISPLAY SSH_AUTH_SOCK"

		set -g @resurrect-dir "$XDG_DATA_HOME/tmux/resurrect"
		set -g @continuum-restore 'on'

		# THEME
		# disable unused functionality in gruvbox theme
		set -g @gruvbox-show-battery false
		set -g @gruvbox-show-network false
		set -g @gruvbox-show-timezone false
		set -g @gruvbox-show-weather false
		set -g @gruvbox-show-fahrenheit false
		# enable non default functionality in gruvbox theme
		set -g @gruvbox-show-left-icon session
		set -g @gruvbox-show-powerline true
		set -g @gruvbox-military-time true
		set -g @gruvbox-day-month true

		bind C-l send-keys 'C-l'
    '';
  };
}


  programs.ssh.addKeysToAgent = "yes";

  home.packages = with pkgs; [
    # essentials
    nvim-pkg
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
}
