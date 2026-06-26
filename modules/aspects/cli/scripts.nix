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
      {
        pkgs,
        osConfig,
        config,
        lib,
        ...
      }:
      let
        whisperSmallModel = pkgs.fetchurl {
          name = "ggml-small.bin";
          url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin";
          sha256 = "0ywqxbziyp2bv72riyjpw4brk9v46d4cfbjfwqvvjrrq0srakqqv";
        };
        dictateIndicator = pkgs.writeShellApplication {
          name = "dictate-indicator";
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
            exec python3 ${pkgs.writeText "dictate-indicator.py" ''
              import math
              import os
              import sys

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
                  def __init__(self, connector, recorder_pid):
                      super().__init__(application_id="dev.repparw.DictateIndicator")
                      self.connector = connector
                      self.recorder_pid = recorder_pid

                  def do_activate(self):
                      window = Gtk.ApplicationWindow(application=self)
                      window.set_decorated(False)
                      window.set_resizable(False)
                      window.set_focusable(False)

                      LayerShell.init_for_window(window)
                      LayerShell.set_layer(window, LayerShell.Layer.OVERLAY)
                      LayerShell.set_anchor(window, LayerShell.Edge.LEFT, True)
                      LayerShell.set_anchor(window, LayerShell.Edge.RIGHT, True)
                      LayerShell.set_anchor(window, LayerShell.Edge.BOTTOM, True)
                      LayerShell.set_margin(window, LayerShell.Edge.BOTTOM, 46)
                      LayerShell.set_keyboard_mode(window, LayerShell.KeyboardMode.NONE)

                      monitor = self.find_monitor()
                      if monitor is not None:
                          LayerShell.set_monitor(window, monitor)

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
                        background: #ff3b5c;
                        border-radius: 999px;
                        min-width: 10px;
                        min-height: 10px;
                      }
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

                      dot = Gtk.Box()
                      dot.add_css_class("dot")
                      dot.set_valign(Gtk.Align.CENTER)

                      bubble.append(dot)
                      bubble.append(Wave())
                      outer.append(bubble)
                      window.set_child(outer)
                      window.present()

                      GLib.timeout_add(500, self.quit_if_recorder_stopped)

                  def find_monitor(self):
                      if not self.connector:
                          return None

                      display = Gdk.Display.get_default()
                      if display is None:
                          return None

                      monitors = display.get_monitors()
                      for index in range(monitors.get_n_items()):
                          monitor = monitors.get_item(index)
                          if getattr(monitor, "get_connector", lambda: None)() == self.connector:
                              return monitor

                      return None

                  def quit_if_recorder_stopped(self):
                      if self.recorder_pid <= 0:
                          return GLib.SOURCE_CONTINUE

                      try:
                          os.kill(self.recorder_pid, 0)
                      except OSError:
                          self.quit()
                          return GLib.SOURCE_REMOVE

                      try:
                          with open(f"/proc/{self.recorder_pid}/stat", "r", encoding="utf-8") as stat:
                              state = stat.read().split()[2]
                      except OSError:
                          self.quit()
                          return GLib.SOURCE_REMOVE

                      if state == "Z":
                          self.quit()
                          return GLib.SOURCE_REMOVE

                      return GLib.SOURCE_CONTINUE


              connector = sys.argv[1] if len(sys.argv) > 1 else ""
              recorder_pid = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 0
              raise SystemExit(Indicator(connector, recorder_pid).run([]))
            ''} "$@"
          '';
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

          ndrop

          (writeShellApplication {
            name = "dictate";
            runtimeInputs = [
              coreutils
              dictateIndicator
              gnugrep
              gnused
              jq
              niri
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
              indicator_pid_file="$state_dir/indicator.pid"
              indicator_log_file="$state_dir/indicator.log"
              audio_file="$state_dir/input.wav"
              transcript_base="$state_dir/transcript"
              transcript_file="$transcript_base.txt"
              model="${whisperSmallModel}"
              threads="$(nproc)"
              max_record_seconds="''${DICTATE_MAX_RECORD_SECONDS:-300}"

              mkdir -p "$state_dir"

              cleanup_state() {
                rm -f "$state_file"
              }

              stop_indicator() {
                if [ -f "$indicator_pid_file" ]; then
                  indicator_pid="$(cat "$indicator_pid_file" 2>/dev/null || true)"
                  if [ -n "''${indicator_pid:-}" ] && kill -0 "$indicator_pid" 2>/dev/null; then
                    kill "$indicator_pid" 2>/dev/null || true
                  fi
                fi

                rm -f "$indicator_pid_file"
              }

              start_indicator() {
                recorder_pid="$1"
                focused_output="$(niri msg --json focused-output 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)"

                dictate-indicator "$focused_output" "$recorder_pid" >> "$indicator_log_file" 2>&1 &
                echo "$!" > "$indicator_pid_file"
              }

              is_recorder_pid() {
                pid="$1"
                [ -r "/proc/$pid/cmdline" ] || return 1
                tr '\0' ' ' < "/proc/$pid/cmdline" | grep -F -- "$audio_file" >/dev/null
              }

              normalize_text() {
                tr '\n' ' ' \
                  | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
              }

              if [ -f "$state_file" ]; then
                read -r recorder_pid < "$state_file"

                if kill -0 "$recorder_pid" 2>/dev/null && is_recorder_pid "$recorder_pid"; then
                  kill -INT "$recorder_pid" 2>/dev/null || true

                  for _ in $(seq 1 50); do
                    kill -0 "$recorder_pid" 2>/dev/null || break
                    sleep 0.1
                  done

                  if kill -0 "$recorder_pid" 2>/dev/null; then
                    kill "$recorder_pid" 2>/dev/null || true
                  fi
                fi

                stop_indicator
                cleanup_state

                if [ ! -s "$audio_file" ]; then
                  exit 1
                fi

                rm -f "$transcript_file"
                whisper-cli \
                  --model "$model" \
                  --file "$audio_file" \
                  --threads "$threads" \
                  --language auto \
                  --no-timestamps \
                  --output-txt \
                  --output-file "$transcript_base" \
                  --no-prints

                if [ ! -s "$transcript_file" ]; then
                  exit 1
                fi

                text="$(normalize_text < "$transcript_file")"

                if [ -z "$text" ]; then
                  exit 1
                fi

                printf '%s' "$text" | wl-copy
                wtype "$text"
                exit 0
              fi

              rm -f "$audio_file" "$transcript_file"
              stop_indicator

              timeout \
                --signal=INT \
                --kill-after=5s \
                "$max_record_seconds" \
                pw-cat \
                --record \
                --media-role Communication \
                --rate 16000 \
                --channels 1 \
                --format s16 \
                --container wav \
                "$audio_file" &

              recorder_pid="$!"
              echo "$recorder_pid" > "$state_file"
              start_indicator "$recorder_pid"
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

        ];
      };
  };
}
