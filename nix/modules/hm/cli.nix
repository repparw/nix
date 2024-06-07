{ inputs, config, lib, pkgs, ... }:

{
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

	home.packages = with pkgs; [
		# essentials
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
		neovim
		yt-dlp
		fzf
		ytfzf

		# CLI tools
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

		tig

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
  	];
}
