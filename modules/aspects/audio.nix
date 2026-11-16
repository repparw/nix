{ den, ... }:
{
  den.aspects.audio = {
    nixos =
      { config, ... }:
      {
        sops.secrets.btDevice = {
          sopsFile = ../../secrets/bluetooth.sops.yaml;
          owner = config.users.users.repparw.name;
          mode = "0400";
        };

        hardware.bluetooth.enable = true;

        # Required by home-manager's dconf module for the blueman settings below.
        programs.dconf.enable = true;

        services = {
          blueman.enable = true;
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

              avantreeStable = {
                "monitor.bluez.rules" = [
                  {
                    matches = [
                      { "device.name" = "bluez_card.00_1D_43_A0_14_D8"; }
                    ];
                    actions.update-props = {
                      "bluez5.roles" = [
                        "a2dp_sink"
                        "a2dp_source"
                      ];
                    };
                  }
                ];
              };

              bluetoothDefault = {
                "monitor.bluez.rules" = [
                  {
                    matches = [
                      {
                        "device.api" = "bluez5";
                        "media.class" = "Audio/Sink";
                      }
                    ];
                    actions.update-props = {
                      "priority.driver" = 2000;
                      "priority.session" = 2000;
                    };
                  }
                ];

                "wireplumber.settings" = {
                  "node.restore-default-targets" = false;
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

              disableEmeetMic = {
                "monitor.alsa.rules" = [
                  {
                    matches = [ { "device.name" = "~alsa_card.usb-EMEET_*"; } ];
                    actions.update-props = {
                      "device.disabled" = true;
                    };
                  }
                  {
                    matches = [ { "node.name" = "~alsa_input.usb-EMEET_*"; } ];
                    actions.update-props = {
                      "node.disabled" = true;
                    };
                  }
                ];
              };
            };
          };
        };
      };

    homeManager =
      { pkgs, ... }:
      {
        dconf.settings."org/blueman/general" = {
          plugin-list = [
            "!ConnectionNotifier"
            "!AutoConnect"
          ];
        };

        home.packages = with pkgs; [
          pwvucontrol

          (writeShellApplication {
            name = "bttoggle";
            runtimeInputs = [
              bluez
              coreutils
            ];
            text = builtins.readFile ../scripts/bttoggle.sh;
          })
        ];
      };
  };
}
