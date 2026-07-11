# shellcheck shell=bash

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

case "${1:-}" in
    screen) geom=$(niri msg --json focused-output | jq -r '.logical | "\(.x),\(.y) \(.width)x\(.height)"') ;;
    area) geom=$(slurp -b "#ff000040" -c "#ff0000ff" -w 2) || exit 0 ;;
    *) echo "Usage: record {screen|area}" >&2; exit 1 ;;
esac

notify-send -t 1000 "Recording starting in 1s" "$1"
sleep 1
wl-screenrec -g "$geom" --audio --audio-device "@DEFAULT_MONITOR@" --low-power=off -f "$output" &
echo "$! $output" > "$state"
