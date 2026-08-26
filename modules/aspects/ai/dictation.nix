{ den, ... }:
{
  den.aspects.ai.provides.dictation = {
    homeManager =
      {
        lib,
        pkgs,
        ...
      }:
      let
        # Upstream ships a prebuilt GTK4 layer-shell OSD, but nixpkgs only
        # builds the quickshell frontend. Patchelf the small standalone binary
        # rather than rebuilding voxtype (its lib pulls in whisper.cpp).
        # Checksummed against upstream's SHA256SUMS.txt at v0.7.5.
        voxtypeOsdGtk4 = pkgs.stdenv.mkDerivation {
          pname = "voxtype-osd-gtk4";
          version = "0.7.5";
          src = pkgs.fetchurl {
            url = "https://github.com/peteonrails/voxtype/releases/download/v0.7.5/voxtype-0.7.5-linux-x86_64-osd-gtk4";
            hash = "sha256-/tgWlVUc7pW7D9N27G3Eljiw/XFEgFBNeKpZewBqWVI=";
          };
          dontUnpack = true;
          nativeBuildInputs = [ pkgs.autoPatchelfHook ];
          buildInputs = with pkgs; [
            cairo
            glib
            gtk4
            gtk4-layer-shell
            stdenv.cc.cc.lib
          ];
          installPhase = ''
            runHook preInstall
            install -Dm755 $src $out/bin/voxtype-osd-gtk4
            runHook postInstall
          '';
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
              frontend = "gtk4";
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
              voxtypeOsdGtk4

              # The daemon looks up the `voxtype-osd` launcher here.
              pkgs.voxtype-vulkan
            ]
          );
        };

      };
  };
}
