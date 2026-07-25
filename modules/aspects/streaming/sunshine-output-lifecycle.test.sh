#!/usr/bin/env bash
set -euo pipefail

output_on_script="$1"
output_off_script="$2"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mock_bin="$test_dir/bin"
runtime_dir="$test_dir/runtime"
command_log="$test_dir/commands"
mkdir -p "$mock_bin" "$runtime_dir"
: > "$command_log"

make_mock() {
  name="$1"
  shift
  printf '%s\n' "#!$BASH" "printf '%s %s\\n' '$name' \"\$*\" >> '$command_log'" "$@" > "$mock_bin/$name"
  chmod +x "$mock_bin/$name"
}

make_mock systemctl \
  'case "$*" in' \
  '  "--user show-environment") printf "%s\n" "NIRI_SOCKET=/run/user/1000/niri" ;;' \
  '  "--user is-active --quiet wpaperd.service") exit 0 ;;' \
  'esac'
make_mock loginctl 'printf "%s\n" "[]"'
make_mock pkill 'exit 0'
make_mock pgrep 'exit 1'
make_mock systemd-inhibit 'exit 0'
make_mock sleep 'exit 0'
make_mock niri \
  'if [ "$*" = "msg --json outputs" ]; then' \
  '  printf "%s\n" "{\"DP-2\":{\"name\":\"DP-2\",\"current_mode\":0,\"logical\":{}}}"' \
  'fi'

PATH="$mock_bin:$PATH" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  SUNSHINE_CONNECTOR_NAME=DP-2 \
  SUNSHINE_OUTPUT_MODE=3840x2160@120 \
  bash "$output_on_script"

wpaperd_marker="$runtime_dir/sunshine-stream/wpaperd-was-active"
if [ ! -e "$wpaperd_marker" ]; then
  echo "output prepare did not remember the active wpaperd service" >&2
  exit 1
fi

stop_line="$(grep -n 'systemctl --user stop wpaperd.service' "$command_log" | cut -d: -f1)"
on_line="$(grep -n 'niri msg output DP-2 on' "$command_log" | cut -d: -f1)"
mode_line="$(grep -n 'niri msg output DP-2 mode 3840x2160@120' "$command_log" | cut -d: -f1)"
if [ "$stop_line" -ge "$on_line" ] || [ "$on_line" -ge "$mode_line" ]; then
  echo "wpaperd stop, output enable, and mode selection happened out of order" >&2
  exit 1
fi

PATH="$mock_bin:$PATH" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  SUNSHINE_CONNECTOR_NAME=DP-2 \
  bash "$output_off_script"

off_line="$(grep -n 'niri msg output DP-2 off' "$command_log" | tail -n 1 | cut -d: -f1)"
start_line="$(grep -n 'systemctl --user start wpaperd.service' "$command_log" | tail -n 1 | cut -d: -f1)"
if [ "$off_line" -ge "$start_line" ]; then
  echo "wpaperd restarted before the streaming output was disabled" >&2
  exit 1
fi
if [ -e "$wpaperd_marker" ]; then
  echo "output reset left a stale wpaperd marker" >&2
  exit 1
fi
