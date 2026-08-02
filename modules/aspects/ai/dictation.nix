{ den, ... }:
{
  den.aspects.ai.provides.dictation = {
    homeManager =
      {
        pkgs,
        ...
      }:
      let
        voxtypePackage = pkgs.voxtype-vulkan;

        voxtypeToggle = pkgs.writeShellApplication {
          name = "voxtype-toggle";
          runtimeInputs = with pkgs; [
            coreutils
            gnugrep
            pipewire
            voxtypePackage
          ];
          text = ''
            set -euo pipefail

            runtime_dir="''${XDG_RUNTIME_DIR:-/tmp}"
            state_file="$runtime_dir/voxtype/state"

            read_state() {
              cat "$state_file" 2>/dev/null || printf 'idle'
            }

            set_playback_suspended() {
              pw-metadata -n default 0 suspend.playback "$1" Spa:Int >/dev/null
            }

            wait_for_idle_then_resume() {
              for _ in $(seq 1 600); do
                [ "$(read_state)" = "idle" ] && break
                sleep 0.1
              done
              set_playback_suspended 0
            }

            case "$(read_state)" in
              recording|streaming)
                voxtype record stop
                wait_for_idle_then_resume &
                ;;
              transcribing)
                voxtype record cancel || true
                wait_for_idle_then_resume &
                ;;
              *)
                set_playback_suspended 1
                if ! voxtype record start; then
                  set_playback_suspended 0
                  exit 1
                fi
                ;;
            esac
          '';
        };
      in
      {
        home.packages = [
          pkgs.quickshell
          voxtypeToggle

          (pkgs.writeShellApplication {
            name = "translate-selection";
            runtimeInputs = with pkgs; [
              coreutils
              gnused
              libnotify
              translate-shell
              wl-clipboard
              wtype
            ];
            text = ''
              notify() {
                notify-send -t 1500 "Translate selection" "$1"
              }

              trim() {
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
              }

              previous="$(wl-paste --no-newline 2>/dev/null || true)"
              sentinel="translate-selection-no-selection-$$"

              printf '%s' "$sentinel" | wl-copy
              sleep 0.05

              wtype -M ctrl -k c -m ctrl
              sleep 0.15

              selection="$(wl-paste --no-newline 2>/dev/null | trim || true)"

              if [ "$selection" = "$sentinel" ] || [ -z "$selection" ]; then
                wtype -M ctrl -k a -m ctrl
                sleep 0.15
                wtype -M ctrl -k c -m ctrl
                sleep 0.15
                selection="$(wl-paste --no-newline 2>/dev/null | trim || true)"
              fi

              if [ "$selection" = "$sentinel" ] || [ -z "$selection" ]; then
                printf '%s' "$previous" | wl-copy
                notify "No selected text found"
                exit 0
              fi

              english="$(printf '%s' "$selection" | trans -brief :en | trim)"

              if [ -z "$english" ]; then
                notify "English translation failed"
                exit 1
              fi

              if [ "$english" != "$selection" ]; then
                translation="$english"
                direction="Spanish -> English"
              else
                translation="$(printf '%s' "$selection" | trans -brief :es | trim)"
                direction="English -> Spanish"
              fi

              if [ -z "$translation" ]; then
                notify "Spanish translation failed"
                exit 1
              fi

              printf '%s' "$translation" | wl-copy
              sleep 0.05
              wtype -M ctrl -k v -m ctrl
              notify "$direction"
            '';
          })
        ];

        services.voxtype = {
          enable = true;
          package = voxtypePackage;
          settings = {
            engine = "whisper";
            whisper = {
              model = "base";
              language = [
                "en"
                "es"
              ];
              translate = false;
              initial_prompt = "NixOS, Nixpkgs, Home Manager, flakes, FlakeHub, sops-nix, dendritic, den, Niri, Quickshell, Voxtype, Wayland.";
            };
            audio.feedback.enabled = true;
            output.notification.on_transcription = false;
            text = {
              filter_filler_words = true;
              replacements = { };
              smart_auto_submit = false;
              spoken_punctuation = true;
            };
            vad = {
              enabled = true;
              backend = "energy";
            };
            osd = {
              enabled = true;
              frontend = "quickshell";
            };
          };
        };

      };
  };
}
