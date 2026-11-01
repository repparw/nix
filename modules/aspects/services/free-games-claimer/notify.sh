#!/usr/bin/env bash
# Runs with '+' privileges from ExecStopPost, not as the browser user.
set -euo pipefail
umask 077

state="${FGC_STATE_DIR:-/var/lib/free-games-claimer}"
data="$state/data"
logs="$state/logs"
previous='{}'
epic='{}'
gog='{}'
if [ -s "$state/notify-state.json" ]; then
  previous=$(cat "$state/notify-state.json")
fi
if [ -s "$data/epic-games.json" ]; then
  epic=$(cat "$data/epic-games.json")
fi
if [ -s "$data/gog.json" ]; then
  gog=$(cat "$data/gog.json")
fi

diffout=$(jq -n \
  --argjson previous "$previous" \
  --argjson epic "$epic" \
  --argjson gog "$gog" \
  -f "$FGC_CLAIM_DIFF")

mapfile -t lines < <(jq -r '.lines[]' <<<"$diffout")
for store in epic-games gog; do
  status="not started"
  if [ -s "$logs/$store.status" ]; then
    status=$(cat "$logs/$store.status")
  fi
  if [ "$status" != 0 ]; then
    lines+=("Store $store run failed (status $status). Check the free-games-claimer service journal and $store.log.")
  fi
  if grep -q "Not signed in anymore" "$logs/$store.log" 2>/dev/null; then
    lines+=("$store needs login: ssh -N -L 6080:127.0.0.1:6080 pi, then open http://localhost:6080/vnc.html")
  fi
  if grep -qi "captcha" "$logs/$store.log" 2>/dev/null; then
    lines+=("$store encountered a captcha. Open noVNC while the run is waiting.")
  fi
done
if [ "${SERVICE_RESULT:-success}" != success ]; then
  lines+=("Claimer service finished with ${SERVICE_RESULT:-unknown} (exit ${EXIT_STATUS:-unknown}).")
fi

# Batch every event instead of silently truncating the report. Keep each
# message below Discord's limit, including supplementary Unicode characters.
header='**free-games-claimer**'
message="$header"
for line in "${lines[@]}"; do
  [ -n "$line" ] || continue
  if (( ${#line} > 850 )); then
    line="${line:0:800}… (truncated; see claim database)"
  fi
  if (( ${#message} + ${#line} + 1 > 900 )); then
    discord-notify post "$message"
    message="$header"
  fi
  message+=$'\n'"$line"
done
if [ "$message" != "$header" ]; then
  discord-notify post "$message"
fi

# Keep previous state if any post fails, so the complete batch is replayable.
jq '.state' <<<"$diffout" >"$state/notify-state.json.new"
mv "$state/notify-state.json.new" "$state/notify-state.json"
