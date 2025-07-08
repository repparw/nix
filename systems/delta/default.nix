{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  jovian = {
    steam = {
      enable = true;
      autoStart = true;
      desktopSession = config.services.displayManager.defaultSession;
    };
    decky-loader = {
      enable = true;
      # extraPackages = [];
    };
    devices.steamdeck = {
      enable = true;
      autoUpdate = true;
    };
  };

  modules = {
    gui.enable = true;
    gaming.enable = true;
    services.enable = true;
    timers.enable = true;
    vm.enable = false;
  };

  networking.hostName = "delta";

  services = {
    sunshine = {
      enable = false;
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
  system.stateVersion = "25.05"; # Did you read the comment?
}
