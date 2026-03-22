{ den, ... }:
{
  den.aspects.cliBasePrograms = {
    nixos =
      { ... }:
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
      };
  };

  den.aspects.cliSystemServices = {
    nixos =
      { ... }:
      {
        services = {
          blueman.enable = true;
          earlyoom.enable = true;
          fail2ban.enable = true;
          gvfs.enable = true;
        };
      };
  };

  den.aspects.cliOpenSsh = {
    nixos =
      { ... }:
      {
        services.openssh = {
          enable = true;
          openFirewall = true;
          settings.PasswordAuthentication = false;
        };
      };
  };

  den.aspects.cliAudio = {
    nixos =
      { ... }:
      {
        services.pipewire = {
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

  den.aspects.cli = {
    includes = [
      den.aspects.cliBasePrograms
      den.aspects.cliSystemServices
      den.aspects.cliOpenSsh
      den.aspects.cliAudio
    ];
  };
}
