# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
	  ./hardware-configuration.nix
	  ../../modules/nixos/cachix.nix
	  ../../modules/nixos/common.nix
	  # ./t440hw.nix
    ];

  networking.hostName = "beta"; # Define your hostname.

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.repparw = {
    isNormalUser = true;
	shell = pkgs.zsh;
    description = "repparw";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

<<<<<<< HEAD
  programs.zsh.enable = true;

  virtualisation.docker = {
	enable = true;
	rootless.enable = true;
	rootless.setSocketVariable = true;
  };

  programs.mosh.enable = true;

  programs.steam = {
	enable = true;
	remotePlay.openFirewall = true;
	gamescopeSession.enable = true;
  };
  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  services.greetd = {
	enable = true;
	vt = 1;
	settings = rec {
	initial_session = {
	  command = "${pkgs.hyprland}/bin/Hyprland";
	  user = "repparw";
	};
	default_session = initial_session;
	};
  };

=======
>>>>>>> c01ce74e (Auto-Commit)
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

<<<<<<< HEAD
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
  };

  hardware.xone.enable = true;
  hardware.xpadneo.enable = true;

  services.logind.lidSwitchExternalPower = "ignore";

=======
>>>>>>> c01ce74e (Auto-Commit)
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
