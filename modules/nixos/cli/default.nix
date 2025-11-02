{
  lib,
  config,
  pkgs,
  ...
}:
{
  programs = {
    adb.enable = true;

    mosh.enable = true;

    nh = {
      enable = true;
      flake = "/home/repparw/src/nix";
      clean = {
        enable = true;
        extraArgs = "--keep 3 --keep-since 7d";
      };
    };

    ssh.startAgent = true;

    fish.enable = true;
  };

  powerManagement.powertop.enable = true;

  services = {
    blueman.enable = true;

    earlyoom.enable = true;

    fail2ban.enable = true;

    gvfs.enable = true;

    tailscale.enable = true;
    tailscale.useRoutingFeatures = "both";

    networkd-dispatcher = {
      enable = true;
      rules."50-tailscale" = {
        onState = [ "routable" ];
        script = ''
          NETDEV="$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")"
          "${lib.getExe pkgs.ethtool}" -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
        '';
      };
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
      ports = [ 10000 ];
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
