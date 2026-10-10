# shellcheck shell=bash
state="${FLEET_UPDATE_STATE:-/var/lib/auto-update}"
outbox="$state/package-events"
[ -d "$outbox" ] || exit 0
exec 9>"$outbox/.delivery.lock"
flock -n 9 || exit 0
key="${FLEET_DEPLOY_KEY:-/home/repparw/.ssh/id_ed25519}"
for entry in "$outbox"/*.json; do
  [ -f "$entry" ] || continue
  event_id=$(jq -er '.event_id | select(test("^[0-9a-f]{64}$"))' "$entry") || continue
  # No deployment lock, Git checkout, CI lookup, or activation is involved.
  # Each attempt is bounded; a failed delivery leaves the exact bytes queued.
  # shellcheck disable=SC2029
  ack=$(timeout 30 ssh -i "$key" -o BatchMode=yes -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    'root@@FLEET_EPSILON_ADDRESS@' /run/current-system/sw/bin/hermes-package-ingest < "$entry" 2>/dev/null) || continue
  if jq -e --arg id "$event_id" 'type == "object" and .event_id == $id and (keys == ["event_id"])' <<<"$ack" >/dev/null 2>&1; then
    rm -f "$entry"
  fi
done
