# shellcheck shell=bash
# Pi-managed runtime readiness evidence for host-owned upstream waits.
#
# Sonarr/Jellyfin and the Moonshine PR227 retirement depend on runtime state
# GitHub CI cannot observe: the Sonarr build actually running on Alpha, the
# Sonarr log gate, Moonshine's PR227 test-build drop-ins, its candidate GC
# root, and stream activity. This probe evaluates those predicates over SSH,
# stores each watcher's status durably, and enqueues an event only when the
# status changes. Delivery is at-least-once, not exactly-once across unknown
# outcomes of a Discord POST. A separate deliverer posts queued events to Discord on its
# own timer, so delivery is independent of deployment success and neither a
# probe failure nor a delivery failure loses a transition.
#
# The Alpha timers stay armed and remain the completion owners until this
# replacement is verified; the probe reports evidence and performs no
# completion action.
#
# Triggers: the fleet-readiness-probe timer and a best-effort call from
# fleet-update deploy after Alpha converges. A nonblocking flock serializes
# overlapping runs; a run skipped by the lock is covered by the next tick.
# Unavailable evidence (Alpha unreachable) keeps the previous status so a
# transient outage never fabricates a transition; the next tick retries.
usage="usage: fleet-readiness-probe [--state DIR] [--watcher sonarr-jellyfin|moonshine-pr227-runtime]"

state="${FLEET_UPDATE_STATE:-/var/lib/auto-update}"
# Substituted at build time with the Alpha deploy address from the fleet registry.
alpha="@FLEET_ALPHA_ADDRESS@"
deploy_key="${FLEET_DEPLOY_KEY:-/home/repparw/.ssh/id_ed25519}"
selected="all"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --state)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      state="$2"
      shift
      ;;
    --watcher)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      selected="$2"
      shift
      ;;
    -h | --help)
      echo "$usage"
      exit 0
      ;;
    *)
      echo "$usage" >&2
      exit 2
      ;;
  esac
  shift
done

case "$selected" in
  all | sonarr-jellyfin | moonshine-pr227-runtime) ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

mkdir -p "$state/readiness" "$state/readiness-events" || exit 1
chmod 0700 "$state/readiness" "$state/readiness-events" 2>/dev/null || true

exec 8>"$state/readiness/.probe.lock"
if ! flock -n 8; then
  echo "another readiness probe owns the lock; skipping"
  exit 0
fi

# True when $1 >= $2: the lowest of the two must be $2.
version_at_least() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# Map collected evidence (JSON) to status<TAB>detail.

# The running Sonarr's build version implies both that Nixpkgs ships the
# Jellyfin 12 auth fix and that Alpha activated it, so the running version is
# the watched condition. The log gate proves the Jellyfin push works: Sonarr
# logs nothing on success, so readiness is the absence of 401s in recent log
# volume.
sonarr_status() {
  local version unauthorized log_read need=4.0.20.3014
  version=$(jq -r '.version // ""' <<<"$1")
  unauthorized=$(jq -r '.unauthorized // ""' <<<"$1")
  log_read=$(jq -r '.log_read // "false"' <<<"$1")
  if [ -z "$version" ]; then
    printf 'waiting\tsonarr process not found\n'
    return 0
  fi
  if ! version_at_least "$version" "$need"; then
    printf 'waiting\tsonarr %s running, need >= %s\n' "$version" "$need"
    return 0
  fi
  if [ "$log_read" != "true" ]; then
    printf 'waiting\tsonarr %s running; recent-log evidence unavailable\n' "$version"
    return 0
  fi
  if [ "$unauthorized" = "true" ]; then
    printf 'waiting\tsonarr %s running; 401 in recent sonarr log\n' "$version"
    return 0
  fi
  if [ "$unauthorized" != "false" ]; then
    printf 'waiting\tsonarr %s running; log 401 check unavailable\n' "$version"
    return 0
  fi
  printf 'ready\tsonarr %s running; no 401 in recent sonarr log\n' "$version"
}

# Runtime readiness evidence for the Moonshine PR227 wait: the external
# test-build drop-ins and candidate GC root are gone AND the running binary
# matches the executable the generated unit selects. This is "runtime
# matches config" evidence: while the declarative test-build aspect is
# enabled, the matching binary is intentionally the test build; retirement
# of the test build itself is the cleanup candidate's deployment.
moonshine_status() {
  local runtime persistent root active exe generated generated_binary active_service
  runtime=$(jq -r '.runtime_override // ""' <<<"$1")
  persistent=$(jq -r '.persistent_override // ""' <<<"$1")
  root=$(jq -r '.candidate_root // ""' <<<"$1")
  active=$(jq -r '.stream_active // ""' <<<"$1")
  exe=$(jq -r '.running_exe // ""' <<<"$1")
  generated=$(jq -r '.generated_exe // ""' <<<"$1")
  generated_binary=$(jq -r '.generated_binary // ""' <<<"$1")
  active_service=$(jq -r '.service_active // ""' <<<"$1")
  if [ "$runtime" = "false" ] && [ "$persistent" = "false" ] && [ "$root" = "false" ] \
    && [ "$active_service" = "true" ] && [[ "$exe" == /nix/store/* ]] \
    && [ "$generated_binary" = "$exe" ]; then
    printf 'ready\tAlpha Moonshine runtime matches its generated unit; external PR227 overrides absent (moonshine %s)\n' "$exe"
    return 0
  fi
  printf 'waiting\tPR227 runtime not verified (runtime=%s persistent=%s root=%s stream_active=%s service_active=%s exe=%s expected=%s)\n' \
    "${runtime:-unknown}" "${persistent:-unknown}" "${root:-unknown}" "${active:-unknown}" \
    "${active_service:-unknown}" "${exe:-unknown}" "${generated_binary:-${generated:-unknown}}"
}

# Collect evidence from Alpha as key=value lines and canonicalize to JSON.
# A remote failure yields a nonzero status, which the caller treats as
# unavailable rather than as an empty observation.
collect() {
  local watcher="$1" raw line key value evidence
  case "$watcher" in
    sonarr-jellyfin)
      # Mirrors watch-sonarr-jellyfin on Alpha: the running build version
      # from the process cmdline, plus the recent-log 401 gate.
      raw=$(timeout 30 ssh -i "$deploy_key" -o BatchMode=yes -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        "root@$alpha" bash -s <<'REMOTE' || return 1
version=$(ps -eo args | grep '[S]onarr -nobrowser' | grep -oE 'sonarr-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d- -f2-)
log_read=false
unauthorized=false
if [ -r /home/containers/config/sonarr/logs/sonarr.txt ]; then
  if recent=$(tail -n 300 /home/containers/config/sonarr/logs/sonarr.txt 2>/dev/null); then
    log_read=true
    if grep -q "401:Unauthorized" <<<"$recent"; then unauthorized=true; fi
  fi
fi
printf 'version=%s\n' "$version"
printf 'log_read=%s\n' "$log_read"
printf 'unauthorized=%s\n' "$unauthorized"
REMOTE
) || return 1
      ;;
    moonshine-pr227-runtime)
      # Mirrors the runtime checks of watch-moonshine-pr227 on Alpha: the
      # exact owned drop-ins, the candidate GC root, stream activity and the
      # binary the generated service currently runs.
      raw=$(timeout 30 ssh -i "$deploy_key" -o BatchMode=yes -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        "root@$alpha" bash -s <<'REMOTE' || return 1
[ -e /run/systemd/system/moonshine.service.d/91-pr227-test.conf ] && runtime=true || runtime=false
[ -e /etc/systemd/system.control/moonshine.service.d/91-pr227-test.conf ] && persistent=true || persistent=false
[ -e /nix/var/nix/gcroots/moonshine-pr227-persistent ] && root=true || root=false
if systemd-inhibit --list --json=short 2>/dev/null | grep -q '"who":"Moonshine"' || pgrep -x gamescope-wl >/dev/null 2>&1; then
  active=true
else
  active=false
fi
exe=""
pid=$(systemctl show moonshine.service -p MainPID --value 2>/dev/null || true)
if [ -n "$pid" ] && [ "$pid" != 0 ]; then
  exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
fi
printf 'runtime_override=%s\n' "$runtime"
printf 'persistent_override=%s\n' "$persistent"
printf 'candidate_root=%s\n' "$root"
printf 'stream_active=%s\n' "$active"
# Verify the active process against the executable the generated service
# ultimately runs. The generated Moonshine unit execs a moonshine-server
# wrapper that in turn execs the real binary, so readiness compares the
# running process with that final binary, not with the wrapper script.
# Missing service or ambiguous binary identity must never report ready.
generated=""
generated_binary=""
config_exec=$(systemctl show moonshine.service -p ExecStart --value 2>/dev/null || true)
if [[ "$config_exec" =~ path=([^\ ;]+) ]]; then
  generated=$(readlink -f "${BASH_REMATCH[1]}" 2>/dev/null || true)
fi
if [ -n "$generated" ] && [ -r "$generated" ] && grep -q '^exec /nix/store/' "$generated" 2>/dev/null; then
  generated_binary=$(sed -n 's|^exec \(/nix/store/[^ ]*/bin/moonshine\)\([ ].*\)\?$|\1|p' "$generated" | head -n1)
fi
[ -n "$generated_binary" ] || generated_binary=$generated
systemctl is-active --quiet moonshine.service && service_active=true || service_active=false
printf 'running_exe=%s\n' "$exe"
printf 'generated_exe=%s\n' "$generated"
printf 'generated_binary=%s\n' "$generated_binary"
printf 'service_active=%s\n' "$service_active"
REMOTE
) || return 1
      ;;
    *)
      echo "unknown watcher: $watcher" >&2
      return 1
      ;;
  esac
  evidence="{}"
  while IFS= read -r line; do
    case "$line" in
      *=*) ;;
      *) continue ;;
    esac
    key=${line%%=*}
    value=${line#*=}
    evidence=$(jq -c --arg k "$key" --arg v "$value" '. + {($k): $v}' <<<"$evidence") || return 1
  done <<<"$raw"
  printf '%s\n' "$evidence"
}

status_for() {
  case "$1" in
    sonarr-jellyfin) sonarr_status "$2" ;;
    moonshine-pr227-runtime) moonshine_status "$2" ;;
  esac
}

# Enqueue exactly one event per status change. The queue entry is created
# atomically (link on a complete temporary), so a crash between enqueue and
# the last-state write replays into a duplicate link that fails closed and
# never produces a second event. Unavailable evidence keeps the previous
# status: the caller never reaches this function for it.
record_transition() {
  local watcher="$1" status="$2" detail="$3" evidence="$4"
  local last_file="$state/readiness/last-$watcher.json"
  local previous previous_since timestamp event_id tmp message event
  previous=$(jq -r '.status // ""' "$last_file" 2>/dev/null || echo "")
  previous_since=$(jq -r '.since_us // 0' "$last_file" 2>/dev/null || echo 0)
  [ "$status" = "$previous" ] && return 0
  timestamp=$(date +%s%6N)
  # A later cycle back to the same status/detail is a new transition. Include
  # the previous *committed* status timestamp, not this attempt's clock, so
  # replay after an enqueue-before-status-write crash keeps the same ID.
  event_id=$(jq -jrn --arg w "$watcher" --arg s "$status" --arg d "$detail" --arg prev "$previous_since" \
    '([$w, $s, $d, $prev] | join("\u0000"))' | sha256sum | cut -d' ' -f1)
  if [ "$status" = "ready" ]; then
    message=$(printf ':white_check_mark: readiness %s: ready — %s' "$watcher" "$detail")
  else
    message=$(printf ':hourglass: readiness %s: %s — %s' "$watcher" "$status" "$detail")
  fi
  event=$(jq -cn \
    --arg watcher "$watcher" \
    --arg status "$status" \
    --arg detail "$detail" \
    --argjson evidence "$evidence" \
    --argjson timestamp_us "$timestamp" \
    --arg event_id "$event_id" \
    --arg message "$message" \
    '{schema_version: 1, kind: "readiness", watcher: $watcher, status: $status,
      detail: $detail, evidence: $evidence, timestamp_us: $timestamp_us,
      event_id: $event_id, message: $message}')
  tmp="$state/readiness-events/.enqueue-$$-$timestamp"
  umask 077
  printf '%s\n' "$event" > "$tmp"
  sync -f "$tmp" 2>/dev/null || true
  if ln "$tmp" "$state/readiness-events/$event_id.json" 2>/dev/null; then
    echo "enqueued: $watcher $status"
  else
    echo "event already queued: $watcher $status ($event_id)"
  fi
  rm -f "$tmp"
  sync -f "$state/readiness-events" 2>/dev/null || true
  jq -cn --arg status "$status" --arg detail "$detail" --argjson since_us "$timestamp" \
    '{status: $status, detail: $detail, since_us: $since_us}' > "$last_file.tmp"
  mv "$last_file.tmp" "$last_file"
}

run_watcher() {
  local watcher="$1" evidence status detail
  if ! evidence=$(collect "$watcher"); then
    echo "unavailable: cannot collect $watcher evidence from $alpha" >&2
    return 0
  fi
  IFS=$'\t' read -r status detail <<<"$(status_for "$watcher" "$evidence")"
  record_transition "$watcher" "$status" "$detail" "$evidence"
}

case "$selected" in
  all)
    run_watcher sonarr-jellyfin
    run_watcher moonshine-pr227-runtime
    ;;
  sonarr-jellyfin) run_watcher sonarr-jellyfin ;;
  moonshine-pr227-runtime) run_watcher moonshine-pr227-runtime ;;
esac
