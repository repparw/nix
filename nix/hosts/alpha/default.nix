# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos/dlsuite.nix
    ../../modules/nixos/timers.nix
    ../../modules/nixos/gaming.nix
  ];

  networking.hostName = "alpha"; # Define your hostname.

  networking.interfaces.enp42s0.wakeOnLan.enable = true;

  users.users.repparw = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3x0wWO/hQmfN3U8x0OxVqKJ7/nQDWcfg3GkyYKKOkf u0_a452@localhost #termux"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR t440"
    ];
    shell = pkgs.zsh;
    description = "repparw";
    extraGroups = [
      "adbusers"
      "networkmanager"
      "wheel"
      "docker"
    ];
  };

  programs.adb.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  #### FSTAB

  fileSystems."/mnt/hdd" = {
    device = "/dev/disk/by-uuid/7a4240ed-59fb-4683-9293-2955c241d199";
    fsType = "btrfs";
    label = "hdd";

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

  systemd.services.logid = {
    wants = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStart = "${pkgs.logiops_0_2_3}/bin/logid";
    };

  };

  services.sunshine = {
    enable = true;
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
