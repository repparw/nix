# shellcheck shell=bash

# Keep independent recordings for the login and nested Moonshine sessions.
umask 077
: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR must be set}"
session="${NIRI_SOCKET:-default}"
session="${session##*/}"
state_dir="$XDG_RUNTIME_DIR/niri-record"
mkdir -p "$state_dir"
state="$state_dir/$session.state"
exec 9>"$state_dir/$session.lock"
flock -x 9

# PID alone is insufficient: a stale state file could target a reused PID.
process_start_time() {
    local pid="$1"
    [[ -r "/proc/$pid/stat" ]] || return 1
    awk '$3 != "Z" { print $22 }' "/proc/$pid/stat"
}

if [[ -f "$state" ]]; then
    pid="" start="" previous_output=""
    read -r pid start previous_output < "$state" || true
    if [[ "$pid" =~ ^[0-9]+$ && "$start" =~ ^[0-9]+$ ]] &&
        [[ "$(process_start_time "$pid" 2>/dev/null)" == "$start" ]]; then
        kill -INT "$pid" || true
        for ((i = 0; i < 100; i++)); do
            [[ "$(process_start_time "$pid" 2>/dev/null)" == "$start" ]] || break
            # A process that was still initializing may miss the first signal.
            if (( i > 0 && i % 20 == 0 )); then
                kill -INT "$pid" || true
            fi
            sleep 0.1
        done
        if [[ "$(process_start_time "$pid" 2>/dev/null)" == "$start" ]]; then
            notify-send "Recording could not be stopped" "$previous_output"
            exit 1
        fi
        rm -f "$state"
        sleep 0.5
        if [[ -s "$previous_output" ]]; then
            printf 'file://%s\n' "$previous_output" | wl-copy --type text/uri-list
        fi
        notify-send "Recording stopped" "$previous_output"
        exit 0
    fi
    rm -f "$state"
fi

case "${1:-}" in
    screen) geom=$(niri msg --json focused-output | jq -r '.logical | "\(.x),\(.y) \(.width)x\(.height)"') ;;
    area) geom=$(slurp -b "#ff000040" -c "#ff0000ff" -w 2) || exit 0 ;;
    *) echo "Usage: record {screen|area}" >&2; exit 1 ;;
esac

mkdir -p "$HOME/Videos/ss"
output="$HOME/Videos/ss/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"
notify-send -t 1000 "Recording starting in 1s" "$1"
sleep 1
# Do not let the recorder inherit the lock descriptor.
wl-screenrec -g "$geom" --audio --audio-device "@DEFAULT_MONITOR@" --low-power=off -f "$output" 9>&- &
pid=$!
if ! start="$(process_start_time "$pid" 2>/dev/null)"; then
    notify-send "Recording failed to start"
    exit 1
fi
printf '%s %s %s\n' "$pid" "$start" "$output" > "$state"
