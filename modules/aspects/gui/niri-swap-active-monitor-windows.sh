# shellcheck shell=bash

focused="$(niri msg --json focused-output | jq -r '.name')"

plan="$(
    niri msg --json workspaces |
        jq -r --arg f "$focused" '
            ([.[] | select(.is_active) | .output] | unique) as $outs
            | [.[] | select(.is_active and .active_window_id != null)
                    | { o: .output, w: .active_window_id }] as $wins
            | (($wins | map(select(.o == $f)) | first) // $wins[0]) as $local
            | (($outs | map(select(. != $local.o)))[0]) as $other_out
            | ($wins | map(select(.o == $other_out)) | first) as $remote
            | [$local.w, $local.o, ($remote.w // $local.w), $other_out] | @tsv
        '
)"

[ -n "$plan" ] || exit 0

read -r local_win local_out remote_win remote_out <<< "$plan"

niri msg action move-window-to-monitor --id "$remote_win" "$local_out"
[ "$local_win" = "$remote_win" ] ||
    niri msg action move-window-to-monitor --id "$local_win" "$remote_out"
niri msg action focus-window --id "$remote_win"
