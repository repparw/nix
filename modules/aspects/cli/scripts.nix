{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.scripts = {
    includes = [ ];

    homeManager =
      {
        pkgs,
        osConfig,
        config,
        ...
      }:
      let
        whisperSmallModel = pkgs.fetchurl {
          name = "ggml-small.bin";
          url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
          sha256 = "0ywqxbziyp2bv72riyjpw4brk9v46d4cfbjfwqvvjrrq0srakqqv";
        };
      in
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

          (writeShellApplication {
            name = "youtube";
            runtimeInputs = [ chromium ];
            text = ''
              exec chromium --password-store=basic --profile-directory=Default --app-id=agimnkijcaahngcdmfeangaknmldooml
            '';
          })

          (writeShellApplication {
            name = "dictate";
            runtimeInputs = [
              coreutils
              gnugrep
              gnused
              libnotify
              pipewire
              whisper-cpp
              wl-clipboard
              wtype
            ];
            text = ''
              set -euo pipefail

              runtime_dir="''${XDG_RUNTIME_DIR:-/tmp}"
              state_dir="$runtime_dir/dictate"
              state_file="$state_dir/state"
              audio_file="$state_dir/input.wav"
              transcript_base="$state_dir/transcript"
              transcript_file="$transcript_base.txt"
              model="${whisperSmallModel}"

              mkdir -p "$state_dir"

              cleanup_state() {
                rm -f "$state_file"
              }

              normalize_text() {
                tr '\n' ' ' \
                  | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
              }

              if [ -f "$state_file" ]; then
                read -r recorder_pid < "$state_file"

                if kill -0 "$recorder_pid" 2>/dev/null; then
                  notify-send -t 1200 "Dictation" "Transcribing..."
                  kill -INT "$recorder_pid" 2>/dev/null || true

                  for _ in $(seq 1 50); do
                    kill -0 "$recorder_pid" 2>/dev/null || break
                    sleep 0.1
                  done

                  if kill -0 "$recorder_pid" 2>/dev/null; then
                    kill "$recorder_pid" 2>/dev/null || true
                  fi
                fi

                cleanup_state

                if [ ! -s "$audio_file" ]; then
                  notify-send -u critical "Dictation" "No audio captured"
                  exit 1
                fi

                rm -f "$transcript_file"
                whisper-cli \
                  --model "$model" \
                  --file "$audio_file" \
                  --language auto \
                  --no-timestamps \
                  --output-txt \
                  --output-file "$transcript_base" \
                  --no-prints

                if [ ! -s "$transcript_file" ]; then
                  notify-send -u critical "Dictation" "No speech detected"
                  exit 1
                fi

                text="$(normalize_text < "$transcript_file")"

                if [ -z "$text" ]; then
                  notify-send -u critical "Dictation" "No speech detected"
                  exit 1
                fi

                printf '%s' "$text" | wl-copy
                wtype "$text"
                notify-send -t 1200 "Dictation" "Inserted text"
                exit 0
              fi

              rm -f "$audio_file" "$transcript_file"
              notify-send -t 1200 "Dictation" "Recording..."

              pw-cat \
                --record \
                --media-role Communication \
                --rate 16000 \
                --channels 1 \
                --format s16 \
                --container wav \
                "$audio_file" &

              echo "$!" > "$state_file"
            '';
          })

          (writeShellApplication {
            name = "codex-desktop-focus";
            runtimeInputs = [
              coreutils
              jq
              niri
            ];
            text = ''
              window_id="$(
                niri msg --json windows \
                  | jq -r '[.[] | select(.app_id == "codex-desktop")] | max_by(.focus_timestamp.secs).id // empty'
              )"

              if [ -n "$window_id" ]; then
                niri msg action focus-window --id "$window_id"
              else
                for proc in /proc/[0-9]*/cmdline; do
                  [ -r "$proc" ] || continue
                  cmdline="$(tr '\0' ' ' < "$proc" 2>/dev/null || true)"
                  case "$cmdline" in
                    *"/opt/codex-desktop/electron "*)
                      case "$cmdline" in
                        *" --type="*) ;;
                        *)
                          pid="''${proc#/proc/}"
                          pid="''${pid%/cmdline}"
                          kill "$pid" 2>/dev/null || true
                          ;;
                      esac
                      ;;
                  esac
                done
                sleep 0.2

                exec codex-desktop
              fi
            '';
          })

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

          (stdenvNoCC.mkDerivation {
            name = "ndrop";
            src = fetchurl {
              url = "https://raw.githubusercontent.com/Schweber/ndrop/main/ndrop";
              hash = "sha256-tzEUaq11x6oVFFIqjZccSkuqMIXRhqYi9Zpx172GiWg=";
            };
            dontUnpack = true;
            nativeBuildInputs = [ makeWrapper ];
            installPhase = ''
              install -Dm755 $src $out/bin/ndrop
              wrapProgram $out/bin/ndrop --prefix PATH : ${
                lib.makeBinPath [
                  niri
                  jq
                  libnotify
                ]
              }
            '';
          })
        ];
      };
  };
}
