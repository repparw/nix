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
        | ($outputs | index($focused)) as $focused_index
        | if $a == null or $focused_index == null then
            empty
          else
            ([range(1; ($outputs | length) + 1)
              | $outputs[(($focused_index + .) % ($outputs | length))]]
              | map(. as $output | $active[]? | select(.output == $output))
              | first) as $b
            | if $b == null then
                empty
              else
                [$a.window, $a.output, $b.window, $b.output] | @tsv
              end
          end
        '
)"

if [ -z "$swap" ]; then
    notify-send -t 2000 "Niri" "Need active windows on two monitors to swap."
    exit 1
fi

read -r focused_window focused_monitor other_window other_monitor <<< "$swap"

niri msg action move-window-to-monitor --id "$focused_window" "$other_monitor"
niri msg action move-window-to-monitor --id "$other_window" "$focused_monitor"
niri msg action focus-window --id "$other_window"
