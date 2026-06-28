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
    includes = [ ];

    homeManager =
      {
        pkgs,
        lib,
        ...
      }:
      let
        system = pkgs.stdenv.hostPlatform.system;
        voxtypeSource = inputs.voxtype;
        voxtypeUnwrapped = voxtypeSource.packages.${system}.voxtype-onnx-unwrapped.overrideAttrs (old: {
          buildFeatures = (old.buildFeatures or [ ]) ++ [ "cohere" ];
          cargoBuildFeatures = (old.cargoBuildFeatures or old.buildFeatures or [ ]) ++ [ "cohere" ];
          cargoCheckFeatures = (old.cargoCheckFeatures or old.buildFeatures or [ ]) ++ [ "cohere" ];
          doCheck = false;
        });
        voxtypePackage = pkgs.symlinkJoin {
          name = "voxtype-onnx-cohere-wrapped-${voxtypeUnwrapped.version}";
          paths = [ voxtypeUnwrapped ];
          buildInputs = [ pkgs.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/voxtype \
              --prefix PATH : "$out/bin" \
              --prefix PATH : ${
                pkgs.lib.makeBinPath (
                  with pkgs;
                  [
                    dotool
                    libnotify
                    pciutils
                    quickshell
                    wl-clipboard
                    xclip
                    xdotool
                    xdg-user-dirs
                    xdg-utils
                    ydotool
                  ]
                )
              } \
              --set ORT_DYLIB_PATH "${pkgs.onnxruntime}/lib/libonnxruntime.so" \
              --prefix LD_LIBRARY_PATH : "${pkgs.onnxruntime}/lib"
          '';
        };

        voxtypeIndicator = pkgs.writeShellApplication {
          name = "voxtype-indicator";
          runtimeInputs = [
            (pkgs.python3.withPackages (
              pythonPkgs: with pythonPkgs; [
                pycairo
                pygobject3
              ]
            ))
          ];
          text = ''
            export GI_TYPELIB_PATH="${pkgs.gdk-pixbuf}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0:${pkgs.graphene}/lib/girepository-1.0:${pkgs.gtk4}/lib/girepository-1.0:${pkgs.gtk4-layer-shell}/lib/girepository-1.0:${pkgs.harfbuzz}/lib/girepository-1.0:${pkgs.pango.out}/lib/girepository-1.0:''${GI_TYPELIB_PATH:-}"
            export LD_LIBRARY_PATH="${
              lib.makeLibraryPath [
                pkgs.cairo
                pkgs.gdk-pixbuf
                pkgs.glib
                pkgs.gobject-introspection
                pkgs.graphene
                pkgs.gtk4
                pkgs.gtk4-layer-shell
                pkgs.harfbuzz
                pkgs.pango.out
              ]
            }:''${LD_LIBRARY_PATH:-}"
            export LD_PRELOAD="${pkgs.gtk4-layer-shell}/lib/libgtk4-layer-shell.so''${LD_PRELOAD:+:$LD_PRELOAD}"
            exec python3 ${pkgs.writeText "voxtype-indicator.py" ''
              import math
              import os
              from pathlib import Path

              import gi

              gi.require_version("Gtk", "4.0")
              gi.require_version("Gdk", "4.0")
              gi.require_version("Gtk4LayerShell", "1.0")

              from gi.repository import Gdk, GLib, Gtk
              from gi.repository import Gtk4LayerShell as LayerShell


              class Wave(Gtk.DrawingArea):
                  def __init__(self):
                      super().__init__()
                      self.phase = 0.0
                      self.set_content_width(58)
                      self.set_content_height(26)
                      self.set_draw_func(self.draw)
                      GLib.timeout_add(80, self.tick)

                  def tick(self):
                      self.phase += 0.42
                      self.queue_draw()
                      return GLib.SOURCE_CONTINUE

                  def draw(self, _area, cr, width, height):
                      cr.set_source_rgba(1.0, 1.0, 1.0, 0.92)
                      bar_width = 5
                      gap = 5
                      bars = 6
                      total = bars * bar_width + (bars - 1) * gap
                      x = (width - total) / 2

                      for index in range(bars):
                          wave = (math.sin(self.phase + index * 0.78) + 1) / 2
                          bar_height = 7 + wave * 15
                          y = (height - bar_height) / 2
                          self.rounded_rectangle(cr, x, y, bar_width, bar_height, 2.5)
                          cr.fill()
                          x += bar_width + gap

                  def rounded_rectangle(self, cr, x, y, width, height, radius):
                      degrees = math.pi / 180
                      cr.new_sub_path()
                      cr.arc(x + width - radius, y + radius, radius, -90 * degrees, 0)
                      cr.arc(x + width - radius, y + height - radius, radius, 0, 90 * degrees)
                      cr.arc(x + radius, y + height - radius, radius, 90 * degrees, 180 * degrees)
                      cr.arc(x + radius, y + radius, radius, 180 * degrees, 270 * degrees)
                      cr.close_path()


              class Indicator(Gtk.Application):
                  def __init__(self):
                      super().__init__(application_id="dev.repparw.VoxTypeIndicator")
                      runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
                      self.state_path = Path(runtime_dir) / "voxtype" / "state"
                      self.window = None
                      self.dot = None
                      self.current_state = None

                  def do_activate(self):
                      self.window = Gtk.ApplicationWindow(application=self)
                      self.window.set_decorated(False)
                      self.window.set_resizable(False)
                      self.window.set_focusable(False)

                      LayerShell.init_for_window(self.window)
                      LayerShell.set_layer(self.window, LayerShell.Layer.OVERLAY)
                      LayerShell.set_anchor(self.window, LayerShell.Edge.LEFT, True)
                      LayerShell.set_anchor(self.window, LayerShell.Edge.RIGHT, True)
                      LayerShell.set_anchor(self.window, LayerShell.Edge.BOTTOM, True)
                      LayerShell.set_margin(self.window, LayerShell.Edge.BOTTOM, 60)
                      LayerShell.set_keyboard_mode(self.window, LayerShell.KeyboardMode.NONE)

                      css = Gtk.CssProvider()
                      css.load_from_data(b"""
                      window {
                        background: transparent;
                      }

                      .bubble {
                        background: rgba(18, 18, 22, 0.86);
                        border: 1px solid rgba(255, 255, 255, 0.18);
                        border-radius: 999px;
                        padding: 10px 15px;
                        box-shadow: 0 10px 34px rgba(0, 0, 0, 0.35);
                      }

                      .dot {
                        border-radius: 999px;
                        min-width: 10px;
                        min-height: 10px;
                      }

                      .dot.recording { background: #ff3b5c; }
                      .dot.transcribing { background: #f0c96b; }
                      .dot.streaming { background: #68b6ff; }
                      """)
                      Gtk.StyleContext.add_provider_for_display(
                          Gdk.Display.get_default(),
                          css,
                          Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
                      )

                      outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
                      outer.set_halign(Gtk.Align.CENTER)

                      bubble = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                      bubble.add_css_class("bubble")
                      bubble.set_valign(Gtk.Align.CENTER)

                      self.dot = Gtk.Box()
                      self.dot.add_css_class("dot")
                      self.dot.set_valign(Gtk.Align.CENTER)

                      bubble.append(self.dot)
                      bubble.append(Wave())
                      outer.append(bubble)
                      self.window.set_child(outer)
                      self.window.present()
                      self.window.set_visible(False)

                      GLib.timeout_add(120, self.poll_state)

                  def read_state(self):
                      try:
                          return self.state_path.read_text(encoding="utf-8").strip()
                      except OSError:
                          return "idle"

                  def poll_state(self):
                      state = self.read_state()
                      if state == self.current_state:
                          return GLib.SOURCE_CONTINUE

                      self.current_state = state
                      if state not in {"recording", "streaming", "transcribing"}:
                          self.window.set_visible(False)
                          return GLib.SOURCE_CONTINUE

                      for name in ("recording", "streaming", "transcribing"):
                          self.dot.remove_css_class(name)
                      self.dot.add_css_class(state)
                      self.window.set_visible(True)
                      return GLib.SOURCE_CONTINUE


              raise SystemExit(Indicator().run([]))
            ''}
          '';
        };

        voxtypeToggle = pkgs.writeShellApplication {
          name = "voxtype-toggle";
          runtimeInputs = with pkgs; [
            coreutils
            gnugrep
            playerctl
            voxtypePackage
            voxtypeIndicator
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
          voxtypeIndicator
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

        home.file.".local/bin/voxtype-toggle".source = "${voxtypeToggle}/bin/voxtype-toggle";
        home.file.".local/bin/voxtype-audio-bridge".source = "${voxtypePackage}/bin/voxtype-audio-bridge";
        xdg.dataFile."voxtype/quickshell".source = "${voxtypeSource}/quickshell";

        programs.voxtype = {
          enable = true;
          package = voxtypePackage;
          engine = "whisper";
          service.enable = true;
          settings = {
            engine = "cohere";
            cohere = {
              model = "cohere-transcribe-q4f16";
              language = "en";
            };
            audio.feedback.enabled = true;
            output.notification.on_transcription = false;
            osd = {
              enabled = true;
              frontend = "quickshell";
            };
          };
        };

        systemd.user.services.voxtype.Service.Environment = [ "VOXTYPE_OSD_FRONTEND=quickshell" ];
      };
  };
}
