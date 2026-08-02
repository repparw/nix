_: {
  den.aspects.cli = {
    nixos =
      { config, ... }:
      {
        programs = {
          mosh = {
            enable = true;
            openFirewall = true;
          };

          nh = {
            enable = true;
            flake = "${config.home-manager.users.repparw.xdg.userDirs.projects}/nix";
            clean = {
              enable = true;
              extraArgs = "--keep 3 --keep-since 7d --keep-one";
            };
          };

          fish.enable = true;
        };

        services = {
          blueman.enable = true;
          earlyoom.enable = true;
          fail2ban.enable = true;
          gvfs.enable = true;
          openssh = {
            enable = true;
            openFirewall = true;
            settings.PasswordAuthentication = false;
          };
          pipewire = {
            enable = true;
            wireplumber.extraConfig = {
              disableAutoswitch = {
                "wireplumber.settings" = {
                  "bluetooth.autoswitch-to-headset-profile" = false;
                };
              };

              disableHwVolume = {
                "monitor.bluez.properties" = {
                  "bluez5.enable-hw-volume" = false;
                };
              };

              preferAvantreeCodec = {
                "device.profile.priority.rules" = [
                  {
                    matches = [
                      { "api.bluez5.address" = "00:1D:43:A0:14:D8"; }
                    ];
                    actions.update-props = {
                      # Avoid aptX-LL, whose transport fails on this device.
                      priorities = [
                        "a2dp-sink"
                        "a2dp-sink-sbc_xq"
                        "a2dp-sink-sbc"
                        "a2dp-sink-aac"
                        "headset-head-unit"
                      ];
                    };
                  }
                ];
              };

              disableHdmi = {
                "monitor.alsa.rules" = [
                  {
                    matches = [ { "device.name" = "alsa_card.pci-0000_2d_00.1"; } ];
                    actions.update-props = {
                      "device.disabled" = true;
                    };
                  }
                ];
              };
            };
          };
        };
      };
  };
}
