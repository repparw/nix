{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  modules = {
    gaming.enable = true;
    services.enable = true;
    timers.enable = true;
    vm.enable = false;
  };

  programs.obs-studio.enable = true;

  networking.hostName = "alpha";

  networking.interfaces.enp42s0.wakeOnLan.enable = true;

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
    sunshine = {
      enable = false; # TODO use sunshine when moving pc to Moque
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
