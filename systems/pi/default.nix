{ config, lib, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko-config.nix
  ];

  networking.hostName = "pi";

  system.nixos.tags =
    let
      cfg = config.boot.loader.raspberryPi;
    in
    [
      "raspberry-pi-${cfg.variant}"
      cfg.bootloader
      config.boot.kernelPackages.kernel.version
    ];

  modules.services = {
    enable = true;
    domain = "home.repparw.me";
    rootDir = "/home/repparw/services";
  };

  boot.loader.systemd-boot.enable = lib.mkForce false;

  services = {
    openssh.ports = [ 2222 ];

    unbound = {
      enable = true;
      settings = {
        server = {
          port = "5335"; # 53 is used by pihole
        };
      };
    };

    archisteamfarm = {
      enable = true;
      settings.SteamOwnerID = "76561198101631906";
      bots.repparw = {
        settings.CustomGamePlayedWhileFarming = "Idling";
        username = "ulisesbritos1";
        passwordFile = config.age.secrets.steamPassword.path;
      };
    };

    # "sudo tailscale up --auth-key=KEY" with the key generated at https://login.tailscale.com/admin/machines/new-linux .
    tailscale.useRoutingFeatures = "server";
    # see also https://github.com/tailscale/tailscale/issues/4432#issuecomment-1112819111
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
