{ den, ... }:
{
  den.aspects.audio = {
    nixos =
      { ... }:
      {
        hardware.bluetooth.enable = true;

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

    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          pwvucontrol

          (writeShellApplication {
            name = "bttoggle";
            runtimeInputs = [ bluez ];
            text = ''
              # device=F8:4E:17:E6:22:D2 # xm4
              device=00:1D:43:A0:14:D8 # avantree

              if bluetoothctl info "$device" | grep -q "Connected: yes"; then
                bluetoothctl disconnect "$device"
              else
                bluetoothctl connect "$device"
              fi
            '';
          })
        ];
      };
  };
}
