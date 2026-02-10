{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  modules = {
    gui.enable = true;
    gaming.enable = true;
    services.enable = true;
    timers.enable = true;
    vm.enable = false;
  };

  programs.obs-studio.enable = true;

  networking.hostName = "alpha";

  # hibernation needs disk swap, not zram
  zramSwap.enable = true;

  #### FSTAB

  fileSystems."/mnt/hdd" = {
    fsType = "btrfs";
    label = "HDD";

    options = [
      "noatime"
      "nodiratime"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "nofail"
    ];
  };

  #### FSTAB

  services = {
    archisteamfarm = {
      enable = true;
      # web-ui.enable = true;
      bots.repparw = {
        settings.OnlineStatus = 0;
        username = "ulisesbritos1";
        passwordFile = config.age.secrets.steamPassword.path;
      };
    };

    beesd.filesystems = {
      root = {
        spec = "LABEL=root";
        hashTableSizeMB = 4096;
        verbosity = "crit";
        extraOptions = [
          "--loadavg-target"
          "5.0"
        ];
      };
      hdd = {
        spec = "LABEL=HDD";
        verbosity = "crit";
        extraOptions = [
          "--loadavg-target"
          "5.0"
        ];
      };
    };

    sunshine = {
      enable = true;
      openFirewall = true;
      capSysAdmin = true;
      settings = {
        output_name = 0;
      };
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
