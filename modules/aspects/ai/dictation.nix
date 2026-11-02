{ den, ... }:
{
  den.aspects.ai.provides.dictation = {
    nixos =
      { config, ... }:
      {
        hardware.uinput.enable = true;

        programs.ydotool = {
          enable = true;
          group = "uinput";
        };

        users.groups.uinput.members = [ config.users.users.repparw.name ];
      };

    homeManager =
      {
        lib,
        pkgs,
        config,
        ...
      }:
      let
        c = config.lib.stylix.colors.withHashtag;

        # Dictation runs Moondream Parakeet Ultra (25-language TDT, incl. es)
        # through the parakeet engine; the onnx build keeps the Vulkan whisper
        # backend for the [whisper] fallback and per-recording --model
        # overrides. See docs/research/parakeet-ultra-evaluation.md.
        voxtypeDictation = pkgs.voxtype-vulkan.override { onnxSupport = true; };
        parakeetUltra = pkgs.callPackage ../../_packages/parakeet-ultra-onnx.nix { };

        voxtypeQsQml = pkgs.fetchFromGitHub {
          owner = "peteonrails";
          repo = "voxtype";
          rev = "dda37ca72b71294d08b0c5bb49c5b24ca590d847";
          hash = "sha256-OT0tVSi9x3U7NwgZU00mojXk3RRWxuFoezpdSknLmmU=";
        };

        voxtypeToggle = pkgs.writeShellApplication {
          name = "voxtype-toggle";
          runtimeInputs = with pkgs; [
            coreutils
            voxtypeDictation
          ];
          text = ''
            set -euo pipefail

            state_file="''${XDG_RUNTIME_DIR:-/tmp}/voxtype/state"

            read_state() {
              cat "$state_file" 2>/dev/null || printf 'idle'
            }

            case "$(read_state)" in
              recording|streaming)
                voxtype record stop
                ;;
              transcribing)
                voxtype record cancel || true
                ;;
              *)
                voxtype record start || exit 1
                ;;
            esac
          '';
        };
      in
      {
        xdg.dataFile."voxtype/quickshell" = {
          source = "${voxtypeQsQml}/quickshell";
          recursive = true;
        };

        home.packages = [
          voxtypeToggle

          # Model-evaluation harness (WER + latency over a fixed sample set);
          # used for the parakeet-ultra comparison and reusable for future
          # dictation-model experiments.
          (pkgs.callPackage ../../_packages/vox-bench.nix { })

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
          package = voxtypeDictation;
          settings = {
            engine = "parakeet";
            parakeet = {
              model = "${parakeetUltra}";
              model_type = "tdt";
            };
            whisper = {
              model = "small";
              language = [
                "en"
                "es"
              ];
              initial_prompt = "NixOS, Nixpkgs, Home Manager, flakes, FlakeHub, sops-nix, dendritic, den, Niri, Voxtype, Wayland.";
            };
            audio.feedback.enabled = true;
            audio.duck_media = true;
            audio.max_duration_secs = 120;
            output.notification.on_transcription = false;
            text = {
              spoken_punctuation = true;
            };
            vad = {
              enabled = true;
              backend = "energy";
            };
            osd = {
              frontend = "quickshell";
              layout = "wide";
              frame = {
                background = "none";
                border = "none";
                halo = false;
              };
              visual.layers = [
                {
                  type = "pulse";
                  source = "rms";
                  color = c.base0D;
                  x = 0.03;
                  y = 0.08;
                  width = 0.94;
                  height = 0.64;
                  gain = 1.2;
                  opacity = 0.14;
                  radius = 10;
                }
                {
                  type = "waveform";
                  color = c.base0C;
                  order = 10;
                  x = 0.03;
                  y = 0.2;
                  width = 0.94;
                  height = 0.6;
                  opacity = 0.9;
                }
              ];
            };
          };
          environment.PATH = lib.makeBinPath (
            with pkgs;
            [
              coreutils
              which
              wl-clipboard
              wtype
              quickshell
              pulseaudio # pactl for Voxtype media ducking
              voxtypeDictation
            ]
          );
        };

      };
  };
}
