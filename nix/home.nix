{ config, pkgs, inputs, ... }:
{
  imports = [
		inputs.hyprland-nix.homeManagerModules.default
		./desktop/sound.nix
		./desktop/hyprland.nix
		];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.username = "repparw";
  home.homeDirectory = "/home/repparw";

  home.stateVersion = "23.11";

  hyprland-nix.homeManagerModules.default
  {
	enable = true;
	reloadCOnfig = true;
	systemdIntegration = true;
  }

  home.packages = with pkgs; [
  		# Essential packages
  		curl
  		wget
  		unzip
  		jq
  		tree
		ffmpeg
  		imagemagick
		tmux
		less

		# CLI tools
		docker-compose
		spotifyd
		keyd
		neovim
		yt-dlp
		tig
		fzf
		ytfzf
		playerctl
		rclone
		ueberzugpp
		libqalculate
		fastfetch
		axel
		manix # man for Nix
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
		ungoogled-chromium
		jellyfin-mpv-shim
		mpv
		mpvScripts.mpris
		feh
		zathura
		vesktop
		spotify-player
		obs-studio
		waydroid
		scrcpy
		unstable.obsidian
		unstable.xpadneo
		# find pomo app in nixpkgs

		# Gaming
		steam
		heroic
		lutris
		xone
		mangohud
	];

	programs = {
		git = { enable = true; userEmail = "ubritos@gmail.com"; userName = "repparw"; };
		zsh = (import = ./zsh.nix; { inherit config, pkgs; });
	}
	

}
