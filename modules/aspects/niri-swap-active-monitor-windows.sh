# shellcheck shell=bash

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

niri msg --json outputs > "$tmpdir/outputs.json"
niri msg --json workspaces > "$tmpdir/workspaces.json"
focused_output="$(niri msg --json focused-output | jq -r '.name')"

swap="$(
    jq -n -r \
        --arg focused "$focused_output" \
        --slurpfile outputs "$tmpdir/outputs.json" \
        --slurpfile workspaces "$tmpdir/workspaces.json" \
        '
        ($outputs[0]
            | to_entries
            | map(select(.value.logical != null))
            | sort_by(.value.logical.x, .value.logical.y)
            | map(.key)) as $outputs
        | ($workspaces[0]
            | map(select(.is_active and (.active_window_id != null))
            | { output, window: .active_window_id })) as $active
        | ($active | map(select(.output == $focused)) | first) as $a
        | (($outputs | index($focused)) as $i
          | if $i == null then $outputs[0]
            else $outputs[(($i + 1) % ($outputs | length))]
            end) as $target
        | ($active
            | map(select(.output == $target))
            | first // null) as $b
        | if $a == null and $b == null then
            empty
          elif $a != null and $b != null then
            ["swap", $a.window, $a.output, $b.window, $b.output] | @tsv
          elif $a != null then
            ["move", $a.window, "", "", $target] | @tsv
          else
            ["move", $b.window, "", "", $focused] | @tsv
          end
        '
)"

if [ -z "$swap" ]; then
    notify-send -t 2000 "Niri" "No active windows to move."
    exit 1
fi

read -r mode focused_window focused_monitor other_window other_monitor <<< "$swap"

if [ "$mode" = "swap" ]; then
    niri msg action move-window-to-monitor --id "$focused_window" "$other_monitor"
    niri msg action move-window-to-monitor --id "$other_window" "$focused_monitor"
    niri msg action focus-window --id "$other_window"
else
    niri msg action move-window-to-monitor --id "$focused_window" "$other_monitor"
    niri msg action focus-window --id "$focused_window"
fi
