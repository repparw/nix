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
      { pkgs, lib, ... }:
      {
        dconf.settings."org/blueman/general" = {
          plugin-list = [ "!ConnectionNotifier" ];
        };

        # Blueman's AutoConnect plugin pages every device listed here once a
        # minute, so the buds (40:5E:F6:CD:0D:CD / 40:5E:F6:CD:0E:F0) are left
        # out on purpose.
        dconf.settings."org/blueman/plugins/autoconnect" = {
          services =
            map
              (
                addr:
                lib.hm.gvariant.mkTuple [
                  addr
                  "00000000-0000-0000-0000-000000000000"
                ]
              )
              [
                "EF:61:5B:0A:3C:30"
                "F8:4E:17:E6:22:D2"
                "00:1D:43:A0:14:D8"
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
            text = ''
              device="''${TOGGLE_BT_DEVICE:-$(cat /run/secrets/btDevice 2>/dev/null || true)}"
              audio_sink="0000110b-0000-1000-8000-00805f9b34fb"
              action="''${1:-toggle}"

              if [ -z "$device" ]; then
                echo "bttoggle: no device configured; set TOGGLE_BT_DEVICE or provision the btDevice secret" >&2
                exit 2
              fi

              info=$(bluetoothctl info "$device" 2>&1 || true)

              is_connected() { [[ $info == *"Connected: yes"* ]]; }
              is_blocked() { [[ $info == *"Blocked: yes"* ]]; }
              refresh_info() { info=$(bluetoothctl info "$device" 2>&1 || true); }

              block_quiet() { bluetoothctl block "$device" >/dev/null 2>&1 || true; }

              do_connect() {
                bluetoothctl unblock "$device" >/dev/null 2>&1 || true
                if ! timeout 20 bluetoothctl connect "$device" >/dev/null 2>&1; then
                  block_quiet
                  exit 3
                fi

                audio_connected=false
                for _ in $(seq 1 10); do
                  if timeout 20 bluetoothctl connect "$device" "$audio_sink" >/dev/null 2>&1; then
                    audio_connected=true
                    break
                  fi
                  sleep 1
                done
                if ! $audio_connected; then
                  block_quiet
                  exit 3
                fi

                refresh_info
                if ! is_connected; then
                  block_quiet
                  exit 3
                fi
              }

              do_disconnect() {
                bluetoothctl disconnect "$device" >/dev/null 2>&1 || true
                block_quiet
              }

              case "$action" in
                connect)
                  do_connect
                  ;;
                disconnect)
                  do_disconnect
                  ;;
                toggle)
                  if is_connected; then
                    do_disconnect
                  else
                    do_connect
                  fi
                  ;;
                status)
                  if is_connected; then connected=1; else connected=0; fi
                  if is_blocked; then blocked=1; else blocked=0; fi
                  printf '{"mac":"%s","blocked":%d,"connected":%d}\n' "$device" "$blocked" "$connected"
                  ;;
                *)
                  echo "Unknown action: $action. Use: connect|disconnect|toggle|status" >&2
                  exit 1
                  ;;
              esac
            '';
          })
        ];
      };
  };
}
