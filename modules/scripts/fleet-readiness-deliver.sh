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
# ready transition runs Alpha's one-shot watch service after Discord accepts
# the post. The notification and the action are acknowledged separately:
# once a post is accepted, its acknowledgment is persisted, so a retrying
# cycle re-runs only the action and an ordinary action failure never
# re-posts the notification (a crash between the accepted post and its
# recorded acknowledgment can still duplicate once). The remote script gates
# on its own runtime conditions and self-deletes its units only after the
# cutover succeeds, so completion is confirmed by Alpha's manager no longer
# finding the units — a start that merely returned success, a regressed
# pre-gate run, or an unreachable Alpha keeps the event queued.

state="${FLEET_UPDATE_STATE:-/var/lib/auto-update}"
outbox="$state/readiness-events"
# Substituted at build time with the Alpha deploy address from the fleet registry.
alpha="@FLEET_ALPHA_ADDRESS@"
deploy_key="${FLEET_DEPLOY_KEY:-/home/repparw/.ssh/id_ed25519}"
[ -d "$outbox" ] || exit 0
exec 9>"$outbox/.delivery.lock"
flock -n 9 || exit 0

complete_sonarr_jellyfin() {
  # Run over the probe's transport (same deploy key, BatchMode, heredoc
  # stdin, host-key policy). The marker positional argument tags the
  # completion transport for tooling; bash -s ignores it. Outcomes:
  #   t3-clean       -> Alpha's manager reports the units not-found/masked:
  #                     the cutover already finished: terminal
  #   t3-done        -> the watch service ran and self-deleted its units:
  #                     completed this cycle
  #   t3-pending     -> the manager answered, the watcher ran or refused,
  #                     but the units remain: retry later
  #   t3-unavailable -> the manager answered nothing: retry
  # Transport failures (empty output, unreachable host) are also retries:
  # never infer a finished cutover from silence.
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
    # The one-shot starts synchronously: when it gated out without the
    # cutover (regressed conditions, lost sudo timestamp), the units remain
    # and the outcome is pending rather than done.
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

# Preserve transition chronology even if multiple events accumulate during
# a Discord outage. Hash-based queue filenames have no chronological order.
# Each entry may carry an adjacent "<name>.json.posted" companion recording
# that discord-notify already accepted its message; the companion matches no
# delivery glob, so it never sees a re-post and dies with its entry.
while IFS= read -r entry; do
  [ -f "$entry" ] || continue
  # Skip anything that is not a well-formed readiness event rather than
  # posting it or deleting it: a malformed entry needs human inspection.
  jq -e '.schema_version == 1 and .kind == "readiness"
    and (.watcher | type == "string" and length > 0)
    and (.status == "ready" or .status == "waiting")
    and (.message | type == "string" and length > 0)' "$entry" >/dev/null 2>&1 || continue
  message=$(jq -r '.message' "$entry")
  ack="$entry.posted"
  if [ -f "$ack" ]; then
    # Already accepted in an earlier cycle: retry only what comes next.
    :
  elif [ ! -f "$entry" ]; then
    continue
  # discord-notify prints the message id on success and fails otherwise.
  elif discord-notify post "$message" >/dev/null 2>&1; then
    : >"$ack" || continue
  else
    continue
  fi
  # Failing the completion action keeps the entry queued: the next cycle
  # retries only the action; the notification stays acknowledged.
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
