{...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  modules.vm.enable = false;

  modules.gaming.enable = true;

  modules.timers.enable = true;

  programs.obs-studio.enable = true;

  modules.dlsuite.enable = true;

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

  ## bind mounts

  fileSystems."/home/repparw/.config/dlsuite/authelia" = {
    depends = [
      "/"
      "/mnt/hdd"
    ];
    device = "/mnt/hdd/docker/authelia";
    options = [
      "bind"
      "ro"
    ];
  };

  fileSystems."/home/repparw/.config/dlsuite/bazarr" = {
    depends = [
      "/"
      "/mnt/hdd"
    ];
    device = "/mnt/hdd/docker/bazarr/backup";
    options = [
      "bind"
      "ro"
    ];
  };

  fileSystems."/home/repparw/.config/dlsuite/grocy" = {
    depends = [
      "/"
      "/mnt/hdd"
    ];
    device = "/mnt/hdd/docker/grocy/data";
    options = [
      "bind"
      "ro"
    ];
  };

  fileSystems."/home/repparw/.config/dlsuite/prowlarr" = {
    depends = [
      "/"
      "/mnt/hdd"
    ];
    device = "/mnt/hdd/docker/prowlarr/Backups";
    options = [
      "bind"
      "ro"
    ];
  };

  fileSystems."/home/repparw/.config/dlsuite/qbittorrent" = {
    depends = [
      "/"
      "/mnt/hdd"
    ];
    device = "/mnt/hdd/docker/qbittorrent/config";
    options = [
      "bind"
      "ro"
    ];
  };

  fileSystems."/home/repparw/.config/dlsuite/radarr" = {
    depends = [
      "/"
      "/mnt/hdd"
    ];
    device = "/mnt/hdd/docker/radarr/Backups";
    options = [
      "bind"
      "ro"
    ];
  };

  fileSystems."/home/repparw/.config/dlsuite/sonarr" = {
    depends = [
      "/"
      "/mnt/hdd"
    ];
    device = "/mnt/hdd/docker/sonarr/Backups";
    options = [
      "bind"
      "ro"
    ];
  };

  fileSystems."/home/repparw/.config/dlsuite/swag" = {
    depends = [
      "/"
      "/mnt/hdd"
    ];
    device = "/mnt/hdd/docker/swag";
    options = [
      "bind"
      "ro"
    ];
  };

  fileSystems."/home/repparw/.config/dlsuite/paper" = {
    depends = [
      "/"
      "/mnt/hdd"
    ];
    device = "/mnt/hdd/docker/paper/export";
    options = [
      "bind"
      "ro"
    ];
  };

  #### FSTAB

  services.sunshine = {
    enable = false; # TODO use sunshine when moving pc to Moque
    capSysAdmin = true;
    settings = {
      output_name = 1;
    };
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
  networking.firewall.trustedInterfaces = [
    "enp42s0"
    "docker0"
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
