{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  modules = {
    gui.enable = true;
    gaming.enable = true;
    services.enable = true;
    timers.enable = true;
    vm.enable = false;
  };

  programs.obs-studio.enable = true;

  networking.hostName = "alpha";

  networking.interfaces.enp42s0.wakeOnLan.enable = true;

  networking.extraHosts = ''
    0.0.0.0 apresolve.spotify.com
  '';

  zramSwap.enable = true;

  #### FSTAB

  fileSystems."/mnt/hdd" = {
    fsType = "btrfs";
    label = "HDD";

    options = [
      "noatime"
      "nodiratime"
    ];
  };

  #### FSTAB

  services = {
    archisteamfarm = {
      enable = true;
      settings.SteamOwnerID = "76561198101631906";
      bots.repparw = {
        settings.CustomGamePlayedWhileFarming = "Idling";
        username = "ulisesbritos1";
        passwordFile = config.age.secrets.steamPassword.path;
      };
    };
    sunshine = {
      enable = true;
      capSysAdmin = true;
      settings = {
        output_name = 1;
      };
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
