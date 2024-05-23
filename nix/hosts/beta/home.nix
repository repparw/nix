{ config, pkgs, inputs, stylix, ... }:
{
  imports = [
		inputs.hyprland-nix.homeManagerModules.default
		../../modules/hm/hyprland.nix
		];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.username = "repparw";
  home.homeDirectory = "/home/repparw";

  wayland.windowManager.hyprland =
  {
    enable = true;
    reloadConfig = true;
    systemdIntegration = true;
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

		# CLI tools
		docker-compose
		spotifyd
		keyd
		neovim
		nil # nix lsp
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
		obsidian
		# find pomo app in nixpkgs


		# Gaming
		steam
		heroic
		lutris
		mangohud
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

  services.ssh-agent.enable = true;

  home.stateVersion = "23.11";

}
