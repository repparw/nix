# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{pkgs, ...}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  networking.hostName = "beta"; # Define your hostname.

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.repparw = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3x0wWO/hQmfN3U8x0OxVqKJ7/nQDWcfg3GkyYKKOkf u0_a452@localhost #termux"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH ubritos@gmail.com #alpha"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDWoVcpGRe7JDzWKFEYlYlHdm3es5vsRS0TjXF7uWkvVqU+ZCJhL5K8uQfPnpooht2uOmVo++b2I3w8Ue/v9J7EQ7JTcS0qEq/V9cgV9T+D/6pEwV60V1JHuBeJcVNv5raTk7OH3T5ZIX4IXpcptBGKqH2BOnYTw4I0uSS0JDBs6K/272DsECjq9qNJgQ5avsTvBIaFbrsXi2dIbG9TTgblLZM0PSG4dfQOYspdgWHg6YAJVs3AXnaK+ZrQGD+QH/uGW41muy11MHXBIPqRtLb0cruSGr6dOLLykMu5s6iqg4Xs41igd/j2k3R+X6TI6prNLiioWGzD0ROVbGzxrmnL+SBKFtgO9hj8gkeLOYC4IfSFmjU6tvKho5W4gHNtCb+dK9jL+jo8REJ9LBXzPB4rIb4IlbgvMGDs89HCNkXH7GXyMxprDd0lNGlwcMP/qE7ReUVjqSCHoiIXtZgFzm8Z8rG2oFwucVn7jYypWERrTHao/Me795IouwuY6hKby1U= deck@steamdeck # change to ed25519?"
    ];
    shell = pkgs.zsh;
    description = "repparw";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  age.identityPaths = ["/home/repparw/.ssh/id_t440"];

  # ignore lid close on AC power
  services.logind.lidSwitchExternalPower = "ignore";

  services.tlp.enable = true;

  services.openssh.ports = [2222];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  networking.firewall.trustedInterfaces = [
    "enp0s25"
    "wlp3s0"
    "docker0"
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
