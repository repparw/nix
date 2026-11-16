# shellcheck shell=bash
# The controller chooses a CI-verified revision. deploy-rs owns builds,
# activations, confirmations and rollback. Service monitoring is independent.
usage="usage: fleet-update deploy [HOST ...] [--force] [--wait-lock SECONDS] [--state DIR]"
fleet_host_json='@FLEET_HOST_JSON@'
package_event="@PACKAGE_EVENT_SCRIPT@"

[ "$#" -gt 0 ] || { echo "$usage" >&2; exit 2; }
[ "$1" = deploy ] || { echo "$usage" >&2; exit 2; }
shift
hosts=()
force=0
lock_wait=0
state="${FLEET_UPDATE_STATE:-/var/lib/auto-update}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --wait-lock)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      lock_wait="$2"
      shift
      ;;
    --state)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      state="$2"
      shift
      ;;
    -h | --help) echo "$usage"; exit 0 ;;
    -*)
      echo "$usage" >&2
      exit 2
      ;;
    *)
      if ! jq -e --arg host "$1" 'has($host)' <<<"$fleet_host_json" >/dev/null; then
        echo "unknown host: $1" >&2
        exit 2
      fi
      for host in "${hosts[@]}"; do
        [ "$host" != "$1" ] || { echo "duplicate host: $1" >&2; exit 2; }
      done
      hosts+=("$1")
      ;;
  esac
  shift
done

case "$lock_wait" in
  '' | *[!0-9]*) echo "--wait-lock requires whole seconds" >&2; exit 2 ;;
esac
if [ "${#hosts[@]}" -eq 0 ]; then
  all_hosts=1
  mapfile -t hosts < <(jq -r 'keys[]' <<<"$fleet_host_json")
else
  all_hosts=0
fi
progress() {
  printf '[%s] fleet-update: %s\n' "$(date +%H:%M:%S)" "$*" >&2
}
notify() {
  discord-notify post "$1" >/dev/null 2>&1 || true
}

mkdir -p "$state"
# Also shared with the independent headless-reboot service. Nix build locks
# alone do not prevent overlapping system activations.
exec 9>"${FLEET_UPDATE_LOCK:-/run/fleet-update.lock}"
if [ "$lock_wait" -gt 0 ]; then
  flock -w "$lock_wait" 9 || { echo "timed out waiting for fleet lock" >&2; exit 1; }
elif ! flock -n 9; then
  progress "another fleet operation is running; skipping"
  exit 0
fi

# PAUSE and rollback-streak belonged to the old controller. The revision
# attempt gate replaces them; clear stale markers so fleet-health does not
# keep reporting a pause that this runner no longer enforces.
rm -f "$state/PAUSE" "$state/rollback-streak"

progress "resolving GitHub main through Nix"
# Resolve once and deploy precisely the revision whose CI status we checked.
# --refresh prevents a stale cached branch tip from hiding a new commit.
revision=$(nix flake metadata --json --refresh github:repparw/nix/main |
  jq -er '.revision | select(test("^[0-9a-f]{40}$"))') || {
    progress "could not resolve main to a commit SHA"
    exit 1
  }

# An unchanged failed revision should not rebuild every morning. This is an
# automatic-attempt marker, not a success claim; a new main SHA can try again.
# --force allows an explicit retry of this exact revision.
if [ "$all_hosts" = 1 ] && [ "$force" = 0 ]; then
  if [ -r "$state/last-attempted-revision" ] &&
    [ "$(cat "$state/last-attempted-revision")" = "$revision" ]; then
    progress "already attempted main ${revision:0:8}; skipping unchanged revision"
    exit 0
  fi
fi

progress "checking CI for main ${revision:0:8}"
# A lock-update commit can be validated on automation/flake-lock before it
# becomes main. Trust only the latest eligible run for this exact SHA.
if ! curl -fsS --max-time 30 \
  "https://api.github.com/repos/repparw/nix/actions/workflows/ci.yml/runs?head_sha=$revision" |
  jq -e --arg sha "$revision" '
    [.workflow_runs[]
     | select(.head_sha == $sha and
       ((.event == "push" and .head_branch == "main") or
        (.event == "workflow_dispatch" and
         (.head_branch == "main" or .head_branch == "automation/flake-lock"))))]
    | (max_by(.run_number) // {})
    | .status == "completed" and .conclusion == "success"
  ' >/dev/null; then
  progress "CI unavailable or not successful for main ${revision:0:8}; skipping"
  exit 1
fi

targets=()
if [ "$all_hosts" = 1 ]; then
  targets=("github:repparw/nix/$revision")
else
  for host in "${hosts[@]}"; do
    targets+=("github:repparw/nix/$revision#$host")
  done
fi

# Preserve the existing package-diff event producer. This data is best-effort
# reporting and never controls deployment or rollback. Reporting and the
# Hermes consumer can be revised independently.
declare -A before_generation=()
deploy_key="${FLEET_DEPLOY_KEY:-/home/repparw/.ssh/id_ed25519}"
ssh_options=(-i "$deploy_key" -o BatchMode=yes -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
remote() {
  local host="$1"
  shift
  local address
  address=$(jq -er --arg host "$host" '.[$host]' <<<"$fleet_host_json") || return 1
  # shellcheck disable=SC2029
  ssh "${ssh_options[@]}" "root@$address" "$@"
}
if [ -r "$deploy_key" ]; then
  for host in "${hosts[@]}"; do
    before=$(remote "$host" readlink /run/current-system 2>/dev/null || true)
    if [[ "$before" == /nix/store/* ]]; then
      before_generation["$host"]="$before"
    fi
  done
fi

# Persist an explicit outcome for Grafana. 0 = successful, 1 = failed,
# 2 = running. An interrupted run stays at 2 and is detected by age.
# Only full-fleet runs update the overall fleet outcome.
record_outcome() {
  local tmp="$state/.last-attempt-status.$$"
  printf '%s\n' "$1" >"$tmp"
  mv -f "$tmp" "$state/last-attempt-status"
}
if [ "$all_hosts" = 1 ]; then
  record_outcome 2
  attempt_tmp="$state/.last-attempted-revision.$$"
  printf '%s\n' "$revision" >"$attempt_tmp"
  mv -f "$attempt_tmp" "$state/last-attempted-revision"
fi

progress "deploy-rs: building and activating ${hosts[*]} at ${revision:0:8}"
# With all hosts selected, deploy-rs owns parallel remote builds and native
# cross-profile rollback. No custom activation ordering or post-soak rollback.
if ! deploy --targets "${targets[@]}" --skip-checks --no-progress; then
  if [ "$all_hosts" = 1 ]; then record_outcome 1; fi
  notify ":warning: fleet deploy-rs failed at ${revision:0:8} (journalctl -u fleet-deploy-run)"
  progress "deploy-rs failed; consult the journal for activation/rollback details"
  exit 1
fi
if [ "$all_hosts" = 1 ]; then record_outcome 0; fi

strip_ansi() {
  awk 'BEGIN { esc = sprintf("%c", 27) } { gsub(esc "\\[[0-9;?]*[A-Za-z]", ""); gsub(/\r/, ""); print }'
}
if [ -r "$deploy_key" ]; then
  mkdir -p "$state/package-events"
  chmod 0700 "$state/package-events" 2>/dev/null || true
  for host in "${hosts[@]}"; do
    previous="${before_generation[$host]-}"
    [ -n "$previous" ] || continue
    current=$(remote "$host" readlink /run/current-system 2>/dev/null || true)
    [[ "$current" == /nix/store/* && "$current" != "$previous" ]] || continue
    if remote "$host" nvd diff "$previous" "$current" 2>/dev/null |
      strip_ansi >"$state/diff-$host.txt"; then
      entry="$state/package-events/$revision-$host.json"
      [ -s "$entry" ] ||
        python3 "$package_event" "$host" "$revision" "$state/diff-$host.txt" \
          --outbox-entry "$entry" >/dev/null 2>&1 || true
    fi
  done
fi

progress "deploy-rs finished at ${revision:0:8}"
notify ":white_check_mark: deploy-rs finished on ${hosts[*]} at ${revision:0:8}"
# Reboot policy is independent: the service checks for a changed kernel/initrd
# and active backups, and has its own nightly timer.
systemctl --no-block start fleet-headless-reboot.service >/dev/null 2>&1 || true
