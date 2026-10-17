# shellcheck shell=bash
# Deliver durable readiness events to Discord.
#
# Runs on its own timer, independent of deployment success and of the probe:
# entries leave the queue only after discord-notify accepts the post, so a
# failed delivery leaves the exact bytes queued for the next cycle. The queue
# provides at-least-once delivery: a network timeout after Discord accepts a
# message may cause a retry and duplicate post. No exactly-once API exists here.
#
# Sonarr/Jellyfin's completion action (drop the weekly Jellyfin scan, restart
# Jellyfin, self-delete the watch units) belonged to Alpha's
# watch-sonarr-jellyfin timer, which is retired now that this replacement is
# verified on Pi. The action rides delivery: a delivered sonarr-jellyfin
# ready transition starts Alpha's one-shot watch service after Discord
# accepts the post. The remote script gates on its own runtime conditions,
# stays idempotent, and self-deletes its units on success; a missing unit is
# terminal clean, not a retryable failure. A failed action leaves the event
# queued, so the next cycle retries notification and action together
# (at-least-once for both; duplicates possible on a lost ack). The probe
# itself never acts, so Moonshine and Sonarr transitions stay observational
# until this hook and the timers cannot orphan the Jellyfin cutover.

state="${FLEET_UPDATE_STATE:-/var/lib/auto-update}"
outbox="$state/readiness-events"
# Substituted at build time with the Alpha deploy address from the fleet registry.
alpha="@FLEET_ALPHA_ADDRESS@"
deploy_key="${FLEET_DEPLOY_KEY:-/home/repparw/.ssh/id_ed25519}"
[ -d "$outbox" ] || exit 0
exec 9>"$outbox/.delivery.lock"
flock -n 9 || exit 0

# Run Alpha's completion one-shot over SSH. Mirror the probe's transport
# (same deploy key, BatchMode, host-key policy and connect timeout). `cat`
# and `cat`'s remote transport cannot distinguish a deleted unit from an
# unreachable host, so the remote script classifies the outcome itself:
# an absent unit is terminal clean (Alpha self-deletes on success), a
# transport or start failure is a retryable error, and only start success
# without a clean verdict counts as completion.
complete_sonarr_jellyfin() {
  local raw rc=0
  raw=$(timeout 320 ssh -i "$deploy_key" -o BatchMode=yes -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    "root@$alpha" bash -c '
      if systemctl --user -M repparw@.host show watch-sonarr-jellyfin.service -p Id >/dev/null 2>&1; then
        systemctl --user -M repparw@.host start watch-sonarr-jellyfin.service
      else
        echo t3-clean
      fi' 2>/dev/null) || rc=$?
  case "$raw" in
    *t3-clean*) return 0 ;;
  esac
  return "$rc"
}

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
    # Failing the completion action keeps the entry queued: the next cycle
    # re-posts (possibly a duplicate) and retries the action.
    if [ "$(jq -r '.watcher // ""' "$entry")" = sonarr-jellyfin ] \
      && [ "$(jq -r '.status // ""' "$entry")" = ready ]; then
      complete_sonarr_jellyfin || continue
    fi
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
