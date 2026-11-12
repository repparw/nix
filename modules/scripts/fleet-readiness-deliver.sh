# shellcheck shell=bash

state="${FLEET_UPDATE_STATE:-/var/lib/auto-update}"
outbox="$state/readiness-events"
alpha="@FLEET_ALPHA_ADDRESS@"
deploy_key="${FLEET_DEPLOY_KEY:-/home/repparw/.ssh/id_ed25519}"
[ -d "$outbox" ] || exit 0
exec 9>"$outbox/.delivery.lock"
flock -n 9 || exit 0

complete_sonarr_jellyfin() {
  local raw
  raw=$(timeout 320 ssh -i "$deploy_key" -o BatchMode=yes -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    "root@$alpha" bash -s fleet-readiness-completion 2>/dev/null <<'REMOTE'
load_state=$(systemctl --user -M repparw@.host show watch-sonarr-jellyfin.service -p LoadState 2>/dev/null)
if [ -z "$load_state" ]; then
  echo t3-unavailable
  exit 1
fi
case "$load_state" in
  LoadState=not-found | LoadState=masked)
    echo t3-clean
    ;;
  *)
    if ! systemctl --user -M repparw@.host start watch-sonarr-jellyfin.service >/dev/null 2>&1; then
      echo t3-pending
      exit 1
    fi
    after=$(systemctl --user -M repparw@.host show watch-sonarr-jellyfin.service -p LoadState 2>/dev/null)
    if [ "$after" = "LoadState=not-found" ] || [ "$after" = "LoadState=masked" ]; then
      echo t3-done
    else
      echo t3-pending
      exit 1
    fi
    ;;
esac
REMOTE
) || true
  case "$raw" in
    *t3-clean* | *t3-done*) return 0 ;;
  esac
  return 1
}

while IFS= read -r entry; do
  [ -f "$entry" ] || continue
  jq -e '.schema_version == 1 and .kind == "readiness"
    and (.watcher | type == "string" and length > 0)
    and (.status == "ready" or .status == "waiting")
    and (.message | type == "string" and length > 0)' "$entry" >/dev/null 2>&1 || continue
  message=$(jq -r '.message' "$entry")
  ack="$entry.posted"
  if [ -f "$ack" ]; then
    :
  elif [ ! -f "$entry" ]; then
    continue
  elif discord-notify post "$message" >/dev/null 2>&1; then
    : >"$ack" || continue
  else
    continue
  fi
  if [ "$(jq -r '.watcher // ""' "$entry")" = sonarr-jellyfin ] \
    && [ "$(jq -r '.status // ""' "$entry")" = ready ]; then
    complete_sonarr_jellyfin || continue
  fi
  rm -f "$entry" "$ack"
done < <(
  for pending in "$outbox"/*.json; do
    [ -f "$pending" ] || continue
    ts=$(jq -r '.timestamp_us // empty' "$pending" 2>/dev/null || true)
    [[ "$ts" =~ ^[0-9]+$ ]] || continue
    printf '%020d\t%s\n' "$ts" "$pending"
  done | sort -k1,1n | cut -f2-
)
