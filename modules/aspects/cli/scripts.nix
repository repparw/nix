{
  den,
  ...
}:
{
  den.aspects.scripts = {
    nixos =
      { ... }:
      {
        nixpkgs.overlays = [
          (final: prev: {
            ndrop = final.callPackage ../../_packages/ndrop.nix { };
          })
        ];
      };

    homeManager =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [

          (writeShellApplication {
            name = "clip2text";
            runtimeInputs = [
              wl-clipboard
              tesseract
            ];
            text = ''
              wl-paste | tesseract - stdout | wl-copy
            '';
          })

          (writeShellApplication {
            name = "clip2qr";
            runtimeInputs = [
              wl-clipboard
              zbar
            ];
            text = ''
              wl-paste --type image/png | zbarimg --raw - | wl-copy
            '';
          })

          (writeShellApplication {
            name = "webapp";
            text = ''
              exec chromium --password-store=basic --app="$1" "''${@:2}"
            '';
          })

          ndrop

          (writeShellApplication {
            name = "bttoggle";
            runtimeInputs = [ bluez ];
            text = ''
              device=F8:4E:17:E6:22:D2 # xm4

              if bluetoothctl info "$device" | grep -q "Connected: yes"; then
                bluetoothctl disconnect "$device"
              else
                bluetoothctl connect "$device"
              fi
            '';
          })

          (writeShellApplication {
            name = "mpvclip";
            runtimeInputs = [
              libnotify
              wl-clipboard
            ];
            text = ''
              notify-send -t 2000 'MPV' 'Loading video...'; mpv --no-terminal "$(wl-paste)"
            '';
          })

          (writeShellApplication {
            name = "hotswap";
            text = ''
              if [ $# -eq 0 ]; then
                echo "Usage: hotswap <file>"
                exit 1
              fi

              file="$1"

              if [ ! -e "$file" ]; then
                echo "Error: File '$file' does not exist"
                exit 1
              fi

              if [ ! -L "$file" ]; then
                echo "File is not a symlink, nothing to do"
                exit 1
              fi

              target="$(readlink -f "$file")"
              temp="$(mktemp)"

              cp "$target" "$temp"

              if nvim "$temp"; then
                rm "$file"
                mv "$temp" "$file"
                echo "Saved."
              else
                rm "$temp"
                echo "Edit canceled."
              fi
            '';
          })

          (writeShellApplication {
            name = "record";
            runtimeInputs = [
              wl-screenrec
              slurp
              niri
              jq
              libnotify
              wl-clipboard
            ];
            text = builtins.readFile ./record.sh;
          })

          (writeShellApplication {
            name = "niri-swap-active-monitor-windows";
            runtimeInputs = [
              niri
              jq
              libnotify
            ];
            text = builtins.readFile ./niri-swap-active-monitor-windows.sh;
          })

        ];
      };
  };
}
