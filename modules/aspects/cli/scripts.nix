{
  den,
  ...
}:
{
  den.aspects.scripts = {
    includes = [ ];

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
            text = ''
              state=/tmp/wl-screenrec.state

              if [ -f "$state" ]; then
                read -r pid output < "$state"
                kill -INT "$pid" 2>/dev/null || true
                while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
                rm -f "$state"
                sleep 0.5
                [ -f "$output" ] && [ -s "$output" ] && echo "file://$output" | wl-copy --type text/uri-list
                notify-send "Recording stopped" "$output"
                exit 0
              fi

              mkdir -p ~/Videos/ss
              output="$HOME/Videos/ss/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"

              case "$1" in
                screen) geom=$(niri msg --json focused-output | jq -r '.logical | "\(.x),\(.y) \(.width)x\(.height)"') ;;
                area)   geom=$(slurp -b "#ff000040" -c "#ff0000ff" -w 2) || exit 0 ;;
                *)      echo "Usage: record {screen|area}" >&2; exit 1 ;;
              esac

              notify-send -t 1000 "Recording starting in 1s" "$1"
              sleep 1
              wl-screenrec -g "$geom" --audio --audio-device "@DEFAULT_MONITOR@" --low-power=off -f "$output" &
              echo "$! $output" > "$state"
            '';
          })

          (writeShellApplication {
            name = "niri-swap-active-monitor-windows";
            runtimeInputs = [
              niri
              jq
              libnotify
            ];
            text = ''
              tmpdir="$(mktemp -d)"
              trap 'rm -rf "$tmpdir"' EXIT

              niri msg --json outputs > "$tmpdir/outputs.json"
              niri msg --json workspaces > "$tmpdir/workspaces.json"
              focused_output="$(niri msg --json focused-output | jq -r '.name')"

              swap="$(
                jq -n -r \
                  --arg focused "$focused_output" \
                  --slurpfile outputs "$tmpdir/outputs.json" \
                  --slurpfile workspaces "$tmpdir/workspaces.json" \
                  '
                    ($outputs[0]
                      | to_entries
                      | map(select(.value.logical != null))
                      | sort_by(.value.logical.x, .value.logical.y)
                      | map(.key)) as $outputs
                    | ($workspaces[0]
                      | map(select(.is_active and (.active_window_id != null))
                      | { output, window: .active_window_id })) as $active
                    | ($active | map(select(.output == $focused)) | first) as $a
                    | ($outputs | index($focused)) as $focused_index
                    | if $a == null or $focused_index == null then
                        empty
                      else
                        ([range(1; ($outputs | length) + 1)
                          | $outputs[(($focused_index + .) % ($outputs | length))]]
                          | map(. as $output | $active[]? | select(.output == $output))
                          | first) as $b
                        | if $b == null then
                            empty
                          else
                            [$a.window, $a.output, $b.window, $b.output] | @tsv
                          end
                      end
                  '
              )"

              if [ -z "$swap" ]; then
                notify-send -t 2000 "Niri" "Need active windows on two monitors to swap."
                exit 1
              fi

              read -r focused_window focused_monitor other_window other_monitor <<< "$swap"

              niri msg action move-window-to-monitor --id "$focused_window" "$other_monitor"
              niri msg action move-window-to-monitor --id "$other_window" "$focused_monitor"
              niri msg action focus-window --id "$other_window"
            '';
          })

        ];
      };
  };
}
