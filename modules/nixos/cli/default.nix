{
  lib,
  config,
  ...
}:
{
  programs = {
    mosh = {
      enable = true;
      openFirewall = true;
    };

    nh = {
      enable = true;
      flake = "/home/repparw/code/nix";
      clean = {
        enable = true;
        extraArgs = "--keep 3 --keep-since 7d";
      };
    };

    fish.enable = true;
  };

  services = {
    blueman.enable = true;

    earlyoom.enable = true;

    fail2ban.enable = true;

    gvfs.enable = true;

    tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "both";
    };

    keyd = {
      enable = lib.mkIf (config.networking.hostName != "alpha") true;
      keyboards = {
        default.settings = {
          main = {
            capslock = "overload(control, esc)";
          };
        };
      };
    };

    openssh = {
      enable = true;
      openFirewall = true;
      settings.PasswordAuthentication = false;
    };

    pipewire = {
      enable = true;
      wireplumber = {
        extraConfig = {
          "disable-autoswitch" = {
            "wireplumber.settings" = {
              "bluetooth.autoswitch-to-headset-profile" = false;
            };
          };
          "disable-hw-volume" = {
            "monitor.bluez.properties" = {
              "bluez5.enable-hw-volume" = false;
            };
          };
        };
      };
    };
  };

}
