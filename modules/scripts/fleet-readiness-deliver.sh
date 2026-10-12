# shellcheck shell=bash
# Deliver durable readiness events to Discord.
#
# Runs on its own timer, independent of deployment success and of the probe:
# entries leave the queue only after discord-notify accepts the post, so a
# failed delivery leaves the exact bytes queued for the next cycle. The queue
# provides at-least-once delivery: a network timeout after Discord accepts a
# message may cause a retry and duplicate post. No exactly-once API exists here.

state="${FLEET_UPDATE_STATE:-/var/lib/auto-update}"
outbox="$state/readiness-events"
[ -d "$outbox" ] || exit 0
exec 9>"$outbox/.delivery.lock"
flock -n 9 || exit 0

# Preserve transition chronology even if multiple events accumulate during
# a Discord outage. Hash-based queue filenames have no chronological order.
while IFS= read -r entry; do
  [ -f "$entry" ] || continue
  # Skip anything that is not a well-formed readiness event rather than
  # posting it or deleting it: a malformed entry needs human inspection.
  jq -e '.schema_version == 1 and .kind == "readiness"
    and (.watcher | type == "string" and length > 0)
    and (.status == "ready" or .status == "waiting")
    and (.message | type == "string" and length > 0)' "$entry" >/dev/null 2>&1 || continue
  message=$(jq -r '.message' "$entry")
  # discord-notify prints the message id on success and fails otherwise.
  if discord-notify post "$message" >/dev/null 2>&1; then
    rm -f "$entry"
  fi
done < <(
  for pending in "$outbox"/*.json; do
    [ -f "$pending" ] || continue
    ts=$(jq -r '.timestamp_us // empty' "$pending" 2>/dev/null || true)
    [[ "$ts" =~ ^[0-9]+$ ]] || continue
    printf '%020d\t%s\n' "$ts" "$pending"
  done | sort -k1,1n | cut -f2-
)
