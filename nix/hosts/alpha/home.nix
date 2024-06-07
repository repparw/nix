{ config, pkgs, unstable, inputs, stylix, ... }:
{
  imports = [
		../../modules/hm/hyprland.nix
		];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.username = "repparw";
  home.homeDirectory = "/home/repparw";

  wayland.windowManager.hyprland = {
	enable = true;
	package = unstable.hyprland;
	xwayland.enable = true;
	systemd.enable = true;
  };

  home.packages = with pkgs; [
  		# Essential packages
		nodejs
  		curl
  		wget
  		unzip
  		jq
  		tree
		ffmpeg
  		imagemagick
		tmux
		less
		base16-schemes

		# nix
		nil # nix lsp
		nh ## yet another nix helper
		manix # man for Nix

		# CLI tools
		docker-compose
		spotifyd
		neovim
		yt-dlp
		tig
		fzf
		ytfzf
		playerctl
		rclone
		melt #ssh ed25519 keys to seed words 
		ueberzugpp
		libqalculate
		fastfetch
		axel
		tlrc # tldr
		nq # Command queue
		lf
		pdfgrep
		catdoc # provides catppt and xls2csv

		# Modern replacements of basic tools
  		bottom
		bat
		colordiff
		duf
		du-dust
		fd
		ripgrep
		zoxide
		eza
		tree

		xmrig-mo

		# GUI
		kitty
		firefox
		chromium
		jellyfin-mpv-shim
		mpv
		mpvScripts.mpris
		mpvScripts.mpv-webm
		mpvScripts.quality-menu
		feh
		zathura
		vesktop
		spotify-player
		obs-studio
		waydroid
		scrcpy
		# find pomo app in nixpkgs


		# Gaming
		steam
		heroic
		lutris
		mangohud
	]++[
	  unstable.obsidian
	];

	programs = {
		git = { 
		  enable = true;
		  userEmail = "ubritos@gmail.com";
		  userName = "repparw";
		  extraConfig = {
			rerere.enabled = true;
		  };
		};
		zsh = {
		  enable = true;
		  enableCompletion = true;
#		  enableGlobbing = true;
		  dotDir = "${config.home.homeDirectory}/.config/zsh";
		};
	};

  programs.ssh.addKeysToAgent = true;

  home.stateVersion = "23.11";

}
