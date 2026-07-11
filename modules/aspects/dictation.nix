{ den, inputs, ... }:
{
  flake-file.inputs.voxtype = {
    url = "github:peteonrails/voxtype/v0.7.5";
    inputs = {
      flake-utils.follows = "flake-utils";
      nixpkgs.follows = "nixpkgs";
    };
  };

  den.aspects.dictation = {
    homeManager =
      {
        pkgs,
        ...
      }:
      let
        system = pkgs.stdenv.hostPlatform.system;
        voxtypeSource = inputs.voxtype;
        voxtypePackage = voxtypeSource.packages.${system}.vulkan;
        voxtypeQuickshell = pkgs.runCommand "voxtype-quickshell-themed" { } ''
          cp -R ${voxtypeSource}/quickshell $out
          chmod -R u+w $out

          substituteInPlace $out/voxtype-shared/Theme.qml \
            --replace-fail 'property color bgColor: Qt.rgba(0.10, 0.10, 0.12, 0.85)' 'property color bgColor: Qt.rgba(0.07, 0.07, 0.09, 0.86)' \
            --replace-fail 'property color accentColor: Qt.rgba(0.40, 0.78, 1.00, 1.0)' 'property color accentColor: Qt.rgba(1.00, 1.00, 1.00, 0.92)' \
            --replace-fail 'property color recordingColor: "#e06c75"' 'property color recordingColor: "#ff3b5c"' \
            --replace-fail 'property color streamingColor: "#61afef"' 'property color streamingColor: "#68b6ff"' \
            --replace-fail 'property color transcribingColor: "#e5c07b"' 'property color transcribingColor: "#f0c96b"' \
            --replace-fail 'property color textColor: "#dcdfe4"' 'property color textColor: "#f2f4f8"' \
            --replace-fail 'property int cornerRadius: 12' 'property int cornerRadius: 999' \
            --replace-fail 'property int padding: 14' 'property int padding: 15' \
            --replace-fail 'property int defaultWidthPx: 400' 'property int defaultWidthPx: 118' \
            --replace-fail 'property int defaultHeightPx: 48' 'property int defaultHeightPx: 46' \
            --replace-fail 'property real defaultOpacity: 0.95' 'property real defaultOpacity: 0.86' \
            --replace-fail 'property real waveformGain: 10.0' 'property real waveformGain: 8.0'

          substituteInPlace $out/OsdSurface.qml \
            --replace-fail 'height: 72' 'height: VT.Theme.defaultHeightPx' \
            --replace-fail 'anchors.bottomMargin: 72' 'anchors.bottomMargin: 60' \
            --replace-fail 'border.width: 2' 'border.width: 1' \
            --replace-fail 'width: 28' 'width: 10' \
            --replace-fail 'text: panel.daemonState === "recording"    ? "󰍬"' 'text: panel.daemonState === "recording"    ? "●"' \
            --replace-fail ': panel.daemonState === "streaming"     ? "󰜟"' ': panel.daemonState === "streaming"     ? "●"' \
            --replace-fail ': panel.daemonState === "transcribing"  ? "󰔟"' ': panel.daemonState === "transcribing"  ? "●"' \
            --replace-fail ':                                          "󰍬"' ':                                          "●"' \
            --replace-fail 'font.pixelSize: 26' 'font.pixelSize: 10' \
            --replace-fail 'width: card.width - 28 - 2 * VT.Theme.padding - 10' 'width: card.width - 10 - 2 * VT.Theme.padding - 10' \
            --replace-fail 'spacing: 4' 'spacing: 0' \
            --replace-fail 'height: 36' 'height: 26' \
            --replace-fail 'height: 6' 'height: 0
                    visible: false'
        '';

        voxtypeToggle = pkgs.writeShellApplication {
          name = "voxtype-toggle";
          runtimeInputs = with pkgs; [
            coreutils
            gnugrep
            playerctl
            voxtypePackage
          ];
          text = ''
            set -euo pipefail

            runtime_dir="''${XDG_RUNTIME_DIR:-/tmp}"
            state_file="$runtime_dir/voxtype/state"
            resume_file="$runtime_dir/voxtype/paused-players"

            read_state() {
              cat "$state_file" 2>/dev/null || printf 'idle'
            }

            pause_playing() {
              mkdir -p "$(dirname "$resume_file")"
              : > "$resume_file"

              while IFS= read -r player; do
                [ -n "$player" ] || continue
                if [ "$(playerctl --player "$player" status 2>/dev/null || true)" = "Playing" ]; then
                  printf '%s\n' "$player" >> "$resume_file"
                  playerctl --player "$player" pause 2>/dev/null || true
                fi
              done < <(playerctl -l 2>/dev/null || true)
            }

            resume_paused() {
              [ -f "$resume_file" ] || return 0

              while IFS= read -r player; do
                [ -n "$player" ] || continue
                playerctl --player "$player" play 2>/dev/null || true
              done < "$resume_file"

              rm -f "$resume_file"
            }

            wait_for_idle_then_resume() {
              for _ in $(seq 1 600); do
                [ "$(read_state)" = "idle" ] && break
                sleep 0.1
              done
              resume_paused
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
                pause_playing
                voxtype record start
                ;;
            esac
          '';
        };
      in
      {
        imports = [ inputs.voxtype.homeManagerModules.default ];

        home.packages = [
          pkgs.quickshell
          voxtypePackage
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

        programs.voxtype = {
          enable = true;
          package = voxtypePackage;
          engine = "whisper";
          service.enable = true;
          settings = {
            engine = "whisper";
            whisper = {
              model = "base";
              language = [
                "en"
                "es"
              ];
              translate = false;
            };
            audio.feedback.enabled = true;
            output.notification.on_transcription = false;
            osd = {
              enabled = true;
              frontend = "quickshell";
            };
          };
        };

        systemd.user.services.voxtype.Service.Environment = [
          "VOXTYPE_OSD_FRONTEND=quickshell"
          "VOXTYPE_OSD_QML_PATH=${voxtypeQuickshell}"
        ];
      };
  };
}
