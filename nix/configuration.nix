# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
let
  unstable = import
    (builtins.fetchTarball https://github.com/nixos/nixpkgs/tarball/master)
    # reuse the current configuration
    { config = config.nixpkgs.config; };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  nix.settings = {
    substituters = ["https://hyprland.cachix.org"];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };

  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "alpha"; # Define your hostname.
  networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Argentina/Buenos_Aires";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_AR.UTF-8";
    LC_IDENTIFICATION = "es_AR.UTF-8";
    LC_MEASUREMENT = "es_AR.UTF-8";
    LC_MONETARY = "es_AR.UTF-8";
    LC_NAME = "es_AR.UTF-8";
    LC_NUMERIC = "es_AR.UTF-8";
    LC_PAPER = "es_AR.UTF-8";
    LC_TELEPHONE = "es_AR.UTF-8";
    LC_TIME = "es_AR.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Nerdfonts
  fonts = {
	packages = with pkgs; [
	  (nerdfonts.override { fonts = [ "FiraCode" ]; })
	];

  # Set default font
    fontconfig.defaultFonts = {
	  "sans-serif" = [ "FiraCode Nerd Font" ];
	  "serif" = [ "FiraCode Nerd Font" ];
	  "monospace" = [ "FiraCode Nerd Font Mono" ];
	};
  };

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    wireplumber.enable = true;
    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.repparw = {
    isNormalUser = true;
	shell = pkgs.zsh;
    description = "repparw";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
	  xmrig-mo

	  kitty

	  # CLI tools
	  keyd
	  neovim
	  yt-dlp
	  ffmpeg
	  git
	  tig
	  fzf
	  ytfzf
	  playerctl
	  docker
	  docker-compose
	  spotifyd
	  rclone
	  wl-clipboard
	  ueberzugpp
	  libqalculate
	  fastfetch
	  axel
	  tlrc # tldr
	  nq # Command queue

	  pdfgrep
	  catdoc # provides catppt and xls2csv

	  # Modern replacements of basic tools
	  bat
	  colordiff
	  duf
	  du-dust
	  fd
	  ripgrep
	  zoxide
	  eza

	  hyprland
	  # install hyprland contrib
	  swaynotificationcenter
	  waybar

	  # GUI
	  feh
	  firefox
	  ungoogled-chromium
	  mpv
	  mpvScripts.mpris
	  zathura
	  heroic
	  lutris
	  vesktop
	  spotify
	  obs-studio
	  kiwix
	  waydroid
	  scrcpy
	  unstable.obsidian
	  xone
	  unstable.xpadneo
	  # find pomo app in nixpkgs

    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! Nano is also installed by default.
	zsh
    wget
	tmux
	mangohud
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  programs.mosh.enable = true;
  programs.zsh.enable = true;

  programs.hyprland = {
  enable = true;
  }

  programs.steam = {
  enable = true;
  remotePlay.openFirewall = true;
  gamescopeSession.enable = true;
  }

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

}
