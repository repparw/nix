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
        # quickshell OSD recipe colors, pulled from the Stylix base16 palette.
        # dictation only applies on GUI hosts, so Stylix is always present.
        c = config.lib.stylix.colors.withHashtag;

        # nixpkgs's voxtype ships the `voxtype-osd-quickshell` launcher but not
        # the quickshell QML tree it needs to render, and not the `qs` runtime.
        # Provide the QML shell from the pinned voxtype source and the runtime
        # from nixpkgs#quickshell. Recipe theming (PR #501) needs voxtype >= 1.0.1.
        voxtypeQsQml = pkgs.fetchFromGitHub {
          owner = "peteonrails";
          repo = "voxtype";
          rev = "dda37ca72b71294d08b0c5bb49c5b24ca590d847"; # v1.0.1
          hash = "sha256-OT0tVSi9x3U7NwgZU00mojXk3RRWxuFoezpdSknLmmU=";
        };

        voxtypeToggle = pkgs.writeShellApplication {
          name = "voxtype-toggle";
          runtimeInputs = with pkgs; [
            coreutils
            voxtype-vulkan
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
        # nixpkgs doesn't ship the voxtype quickshell QML tree; install it so
        # `voxtype-osd-quickshell` finds shell.qml. Sourced from the pinned
        # voxtype repo so it matches the recipe config shipped above.
        xdg.dataFile."voxtype/quickshell" = {
          source = "${voxtypeQsQml}/quickshell";
          recursive = true;
        };

        home.packages = [
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
          package = pkgs.voxtype-vulkan;
          settings = {
            engine = "whisper";
            whisper = {
              model = "base";
              language = [
                "en"
                "es"
              ];
              translate = false;
              initial_prompt = "NixOS, Nixpkgs, Home Manager, flakes, FlakeHub, sops-nix, dendritic, den, Niri, Voxtype, Wayland.";
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
              layout = "wide";
              frame = {
                background = "none";
                border = "none";
                glow = true;
                halo = false;
              };
              visual.layers = [
                {
                  type = "pulse";
                  source = "rms";
                  color = c.base0D;
                  order = 0;
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
                  source = "peak";
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
          # The daemon spawns `voxtype-osd` and output typing needs wtype;
          # give the service an explicit PATH instead of relying on the
          # module's display-gated default. WAYLAND_DISPLAY itself is
          # inherited from the user manager environment (imported by niri).
          environment.PATH = lib.makeBinPath (
            with pkgs;
            [
              coreutils
              which
              wl-clipboard
              wtype
              quickshell

              # The daemon looks up the `voxtype-osd` launcher here.
              pkgs.voxtype-vulkan
            ]
          );
        };

      };
  };
}
