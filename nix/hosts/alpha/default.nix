# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
	  ./hardware-configuration.nix
	  ../../modules/nixos/cachix.nix
	  ../../modules/nixos/common.nix
    ];


  networking.hostName = "alpha"; # Define your hostname.

  users.users.repparw = {
    isNormalUser = true;
	shell = pkgs.zsh;
    description = "repparw";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };


  virtualisation.docker = {
	enable = true;
	rootless.enable = true;
	rootless.setSocketVariable = true;
  };


 #programs.steam = {
 #      enable = true;
 #      remotePlay.openFirewall = true;
 #      gamescopeSession.enable = true;
 #};

  services.sunshine.enable = true;

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
