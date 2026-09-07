# shellcheck shell=bash
usage="usage: fleet-update <promote|deploy> [--host alpha|pi|epsilon] [--force] [--wait-lock SECONDS] [--state DIR]"

[ "$#" -gt 0 ] || { echo "$usage" >&2; exit 2; }
action="$1"
shift
case "$action" in
  promote | deploy) ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

force=0
lock_wait=0
requested_host=all
state="${FLEET_UPDATE_STATE:-/var/lib/auto-update}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --wait-lock)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      lock_wait="$2"
      shift
      ;;
    --host)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      requested_host="$2"
      shift
      ;;
    --state)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      state="$2"
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

case "$requested_host" in
  all | alpha | pi | epsilon) ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
case "$lock_wait" in
  '' | *[!0-9]*) echo "--wait-lock requires whole seconds" >&2; exit 2 ;;
esac

if [ "$action" = promote ] && [ "$requested_host" != all ]; then
  echo "promote does not accept --host" >&2
  exit 2
fi
if [ "$force" = 1 ] && [ "$requested_host" = all ]; then
  echo "--force requires an explicit --host" >&2
  exit 2
fi
if [ "$force" = 1 ] && [ "$action" = promote ]; then
  echo "promote does not accept --force" >&2
  exit 2
fi

mkdir -p "$state"
exec 9>"${FLEET_UPDATE_LOCK:-/run/fleet-update.lock}"
if [ "$lock_wait" -gt 0 ]; then
  if ! flock -w "$lock_wait" 9; then
    echo "timed out waiting ${lock_wait}s for another fleet update" >&2
    exit 1
  fi
elif ! flock -n 9; then
  echo "another fleet update is already running"
  exit 0
fi

if [ -e "$state/PAUSE" ] && [ "$force" = 0 ]; then
  echo "automation paused via $state/PAUSE"
  exit 0
fi
if [ -e "$state/PAUSE" ]; then
  echo "explicit force overrides automation pause at $state/PAUSE"
fi

api="https://discord.com/api/v10/channels/1515064288191053979/messages"
notify() { # content
  [ -r /run/secrets/hermes-env ] || return 0
  # shellcheck disable=SC1091
  source /run/secrets/hermes-env
  curl -sS -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg c "$1" '{content: $c}')" "$api" >/dev/null || true
}

notify_file() { # content, file
  [ -r /run/secrets/hermes-env ] || return 0
  [ -s "$2" ] || return 0
  # shellcheck disable=SC1091
  source /run/secrets/hermes-env
  curl -sS -m 30 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -F "payload_json=$(jq -n --arg c "$1" '{content: $c}')" \
    -F "files[0]=@$2" "$api" >/dev/null || true
}

repo="$state/src"
if [ -d "$repo/.git" ]; then
  git -C "$repo" fetch origin main
  if [ "$(git -C "$repo" rev-parse --is-shallow-repository)" = true ]; then
    git -C "$repo" fetch --unshallow origin
  fi
  git -C "$repo" reset --hard origin/main
else
  git clone https://github.com/repparw/nix "$repo"
fi
cd "$repo" || exit 1

deploy_key="${FLEET_DEPLOY_KEY:-/home/repparw/.ssh/id_ed25519}"
if [ ! -r "$deploy_key" ]; then
  echo "deployment key is not readable: $deploy_key" >&2
  exit 1
fi
ssh_options=(
  -i "$deploy_key"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
)

host_address() {
  case "$1" in
    alpha) echo @FLEET_ALPHA_ADDRESS@ ;;
    pi) echo @FLEET_PI_ADDRESS@ ;;
    epsilon) echo @FLEET_EPSILON_ADDRESS@ ;;
  esac
}

remote() { # host, command...
  local host="$1"
  shift
  # Arguments are intentionally expanded by this client-side wrapper.
  # shellcheck disable=SC2029
  ssh "${ssh_options[@]}" "root@$(host_address "$host")" "$@"
}

host_is_idle() {
  local host="$1" inhibitors blocking_sleep

  # A locked physical session can still be serving an active remote game or
  # media stream.  Those applications publish the standard systemd sleep
  # inhibitor; delay-mode power-management hooks are not evidence of use.
  if ! inhibitors=$(remote "$host" systemd-inhibit --list --json=short --no-pager); then
    echo "$host inhibitor state is unavailable" >&2
    return 1
  fi
  if ! jq -e 'type == "array"' <<< "$inhibitors" >/dev/null; then
    echo "$host returned invalid inhibitor state" >&2
    return 1
  fi
  blocking_sleep=$(
    jq -r '
      .[]
      | select(.mode == "block")
      | select(((.what // "") | split(":")) | index("sleep") != null)
      | "\(.who // .comm // "unknown") (\(.why // "no reason"))"
    ' <<< "$inhibitors"
  ) || return 1
  if [ -n "$blocking_sleep" ]; then
    echo "$host has a block-mode sleep inhibitor:" >&2
    printf '%s\n' "$blocking_sleep" >&2
    return 1
  fi

  remote "$host" bash -s <<'EOF'
locked=""
idle=""
session_state=""
session_type=""
sessions=$(loginctl list-sessions --no-legend 2>/dev/null) || exit 1
[ -z "$sessions" ] && exit 0
while read -r sess _; do
  [ -n "$sess" ] || continue
  class=$(loginctl show-session "$sess" -p Class --value 2>/dev/null) || exit 1
  is_remote=$(loginctl show-session "$sess" -p Remote --value 2>/dev/null) || exit 1
  session_type=$(loginctl show-session "$sess" -p Type --value 2>/dev/null) || exit 1
  [ "$class" = user ] || continue
  [ "$is_remote" = no ] || continue
  case "$session_type" in
    wayland | x11) ;;
    *) continue ;;
  esac

  locked=$(loginctl show-session "$sess" -p LockedHint --value 2>/dev/null) || exit 1
  idle=$(loginctl show-session "$sess" -p IdleHint --value 2>/dev/null) || exit 1
  session_state=$(loginctl show-session "$sess" -p State --value 2>/dev/null) || exit 1
  [ "$locked" = yes ] && continue
  [ "$idle" = yes ] && continue
  [ -n "$session_state" ] && [ "$session_state" != active ] && continue
  exit 1
done <<< "$sessions"
EOF
}

http_code() {
  [ "$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$1" || true)" = "$2" ]
}

health_once() {
  local host="$1" state_now
  state_now=$(remote "$host" systemctl is-system-running 2>/dev/null || true)
  case "$state_now" in
    running | degraded) ;;
    *) return 1 ;;
  esac

  case "$host" in
    epsilon)
      remote epsilon systemctl is-active --quiet \
        container@hermes.service container@authelia.service \
        container@miniflux.service container@archisteamfarm.service traefik.service || return 1
      http_code https://repparw.com/ 200 || return 1
      http_code https://rss.repparw.com/healthcheck 200 || return 1
      ;;
    pi)
      remote pi systemctl is-active --quiet \
        container@homeassistant.service traefik.service || return 1
      http_code https://home.repparw.com/ 200 || return 1
      ;;
    alpha)
      remote alpha systemctl is-active --quiet \
        container@jellyfin.service container@paperless.service || return 1
      http_code http://192.168.0.18:8096/health 200 || return 1
      ;;
  esac
}

soak() {
  local host="$1" attempts="${FLEET_SOAK_ATTEMPTS:-10}"
  local interval="${FLEET_SOAK_INTERVAL_SECONDS:-60}"
  local settle="${FLEET_SOAK_SETTLE_SECONDS:-60}" passes=0 i=0
  sleep "$settle"
  while [ "$i" -lt "$attempts" ]; do
    if health_once "$host"; then
      passes=$((passes + 1))
    else
      passes=0
    fi
    [ "$passes" -ge 2 ] && return 0
    i=$((i + 1))
    sleep "$interval"
  done
  return 1
}

free_kb() { df -k /nix | awk 'NR == 2 { print $4 }'; }
if [ "$(free_kb)" -lt $((6 * 1024 * 1024)) ]; then
  notify ":warning: fleet update aborted: $(df -h /nix | awk 'NR == 2 { print $4 }') free on /nix"
  exit 1
fi

write_candidate() { # revision, parent, status
  local tmp="$state/candidate.new.$$"
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$tmp"
  mv "$tmp" "$state/candidate"
}

read_candidate() {
  candidate_revision=""
  candidate_parent=""
  candidate_status=""
  [ -r "$state/candidate" ] || return 1
  IFS=$'\t' read -r candidate_revision candidate_parent candidate_status < "$state/candidate"
  [[ "$candidate_revision" =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ "$candidate_parent" =~ ^[0-9a-f]{40}$ ]] || return 1
  case "$candidate_status" in
    prepared | published | completed | stale | reverted) ;;
    *) return 1 ;;
  esac
}

candidate_commit_is_safe() {
  local revision="$1" parent="$2" changed
  [ "$(git rev-parse "$revision^")" = "$parent" ] || return 1
  [ "$(git show -s --format='%an <%ae>' "$revision")" = "pi-auto-update <pi-auto-update@repparw.com>" ] || return 1
  [ "$(git show -s --format=%s "$revision")" = "flake.lock: Update" ] || return 1
  changed=$(git diff-tree --no-commit-id --name-only -r "$revision") || return 1
  [ "$changed" = flake.lock ]
}

cleanup_candidate_roots() { # revision
  local host
  for host in epsilon pi alpha; do
    remote "$host" rm -f "/nix/var/nix/gcroots/fleet-update/$1" 2>/dev/null || true
  done
}

preflight_hosts() {
  local host
  for host in "$@"; do
    nix eval ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath" --raw >/dev/null
  done
}

if [ "$action" = promote ]; then
  if ! health_once pi; then
    notify ":warning: fleet promotion aborted: pi health gate is failing before the lock bump"
    exit 1
  fi

  revision=$(git rev-parse HEAD)
  if read_candidate; then
    case "$candidate_status" in
      prepared | published)
        if [ "$candidate_revision" = "$revision" ] && [ "$(cat "$state/deployed-revision" 2>/dev/null || true)" != "$revision" ]; then
          notify ":warning: fleet promotion deferred: candidate ${revision:0:8} has not fully converged"
          echo "candidate ${revision:0:8} has not fully converged; run fleet-update deploy first" >&2
          exit 1
        fi
        cleanup_candidate_roots "$candidate_revision"
        write_candidate "$candidate_revision" "$candidate_parent" stale
        ;;
      completed | stale | reverted)
        cleanup_candidate_roots "$candidate_revision"
        ;;
    esac
  fi

  timeout 20m systemctl start restic-backups-offsite.service ||
    notify ":information_source: fleet promotion proceeding without a fresh pi snapshot"

  nix flake update
  if git diff --exit-code flake.lock >/dev/null; then
    echo "lock unchanged; nothing to promote"
    exit 0
  fi

  current_system=$(nix eval --impure --raw --expr builtins.currentSystem)
  nix build ".#checks.$current_system.deploy-schema" --no-link
  preflight_hosts epsilon pi alpha

  git config user.name pi-auto-update
  git config user.email pi-auto-update@repparw.com
  git add flake.lock
  git commit -m "flake.lock: Update"
  revision=$(git rev-parse HEAD)
  parent=$(git rev-parse HEAD^)
  write_candidate "$revision" "$parent" prepared
  export GIT_SSH_COMMAND="ssh -i $deploy_key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
  if ! git push git@github.com:repparw/nix.git HEAD:main; then
    notify ":warning: fleet promotion aborted: lock push failed; no host was changed"
    exit 1
  fi
  write_candidate "$revision" "$parent" published
  git push git@gitlab.com:repparw/nix.git HEAD:main ||
    notify ":warning: fleet promotion landed on GitHub but the GitLab mirror push failed"
  notify ":arrow_up: fleet candidate ${revision:0:8} published; deployment is a separate transaction"
  exit 0
fi

if [ "$requested_host" = all ]; then
  hosts=(epsilon pi alpha)
else
  hosts=("$requested_host")
fi

current_system=$(nix eval --impure --raw --expr builtins.currentSystem)
nix build ".#checks.$current_system.deploy-schema" --no-link
# Force every real profile path before the first canary changes. Evaluation or
# mixed-architecture errors are preflight failures, not rollback events.
preflight_hosts "${hosts[@]}"

revision=$(git rev-parse HEAD)
printf '%s\n' "$revision" > "$state/target-revision"
candidate_active=0
if read_candidate \
  && { [ "$candidate_status" = published ] || [ "$candidate_status" = prepared ]; } \
  && [ "$candidate_revision" = "$revision" ] \
  && candidate_commit_is_safe "$candidate_revision" "$candidate_parent"; then
  candidate_active=1
fi

declare -A before_generation
deployed=()
deferred=()
failure_host=""

deploy_one() {
  local host="$1" running_revision before after_generation activity_gate

  running_revision=$(remote "$host" nixos-version --configuration-revision 2>/dev/null || true)
  if [ "$running_revision" = "$revision" ]; then
    echo "$host already runs ${revision:0:8}"
    if [ "$candidate_active" = 1 ]; then
      before=$(cat "$state/before-$revision-$host" 2>/dev/null || true)
      if [[ "$before" == /nix/store/* ]]; then
        touch "$state/reached-$revision-$host" || return 1
      fi
    fi
    return 2
  fi

  activity_gate=$(nix eval --json ".#nixosConfigurations.$host.config.modules.fleet-update.activityGate") || return 1
  case "$activity_gate" in
    true)
      if [ "$force" = 0 ] && ! host_is_idle "$host"; then
        echo "$host has an active graphical session or is unavailable; deferring it"
        notify ":information_source: fleet update deferred $host (active or unavailable) at ${revision:0:8}"
        deferred+=("$host")
        return 2
      fi
      ;;
    false) ;;
    *)
      echo "$host returned an invalid activity-gate value: $activity_gate" >&2
      return 1
      ;;
  esac

  before=$(remote "$host" readlink /run/current-system) || return 1
  if [[ "$before" != /nix/store/* ]]; then
    echo "$host returned an invalid current-system path: ${before:-empty}" >&2
    return 1
  fi
  before_generation["$host"]=$before
  if [ "$candidate_active" = 1 ]; then
    printf '%s\n' "$before" > "$state/before-$revision-$host" || return 1
    remote "$host" mkdir -p /nix/var/nix/gcroots/fleet-update || return 1
    remote "$host" ln -sfn "$before" "/nix/var/nix/gcroots/fleet-update/$revision" || return 1
  fi
  if ! deploy ".#$host" --skip-checks; then
    return 1
  fi

  deployed+=("$host")
  if [ "$candidate_active" = 1 ]; then
    touch "$state/reached-$revision-$host" || return 1
  fi
  running_revision=$(remote "$host" nixos-version --configuration-revision 2>/dev/null || true)
  if [ "$running_revision" != "$revision" ]; then
    echo "$host activated revision ${running_revision:-unknown}, expected $revision" >&2
    return 1
  fi
  if ! soak "$host"; then
    return 1
  fi

  after_generation=$(remote "$host" readlink /run/current-system)
  remote "$host" nix store diff-closures "${before_generation[$host]}" "$after_generation" \
    > "$state/diff-$host.txt" || true
  notify_file "**$host deployed** — ${revision:0:8}" "$state/diff-$host.txt"
}

for host in "${hosts[@]}"; do
  rc=0
  deploy_one "$host" || rc=$?
  if [ "$rc" = 1 ]; then
    failure_host="$host"
    break
  fi
done

if [ -n "$failure_host" ]; then
  streak=$(( $(cat "$state/rollback-streak" 2>/dev/null || echo 0) + 1 ))
  printf '%s\n' "$streak" > "$state/rollback-streak" \
    || notify ":warning: could not persist the fleet rollback streak"
  note=""
  if [ "$streak" -ge 2 ]; then
    if touch "$state/PAUSE"; then
      note=" — automation PAUSED (breaker)"
    else
      note=" — WARNING: failed to persist the automation pause"
    fi
  fi

  if [ "$candidate_active" = 1 ]; then
    export GIT_SSH_COMMAND="ssh -i $deploy_key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    remote_revision=""
    revert_published=0
    if git fetch origin main; then
      remote_revision=$(git rev-parse origin/main 2>/dev/null || true)
    fi
    if [ "$remote_revision" = "$candidate_revision" ] \
      && candidate_commit_is_safe "$candidate_revision" "$candidate_parent"; then
      if git reset --hard "$candidate_revision" \
        && git config user.name pi-auto-update \
        && git config user.email pi-auto-update@repparw.com \
        && git revert --no-edit "$candidate_revision" \
        && git push git@github.com:repparw/nix.git HEAD:main; then
        revert_published=1
        write_candidate "$candidate_revision" "$candidate_parent" reverted \
          || notify ":warning: candidate revert was published but its status could not be persisted"
        git push git@gitlab.com:repparw/nix.git HEAD:main || true
      else
        notify ":rotating_light: CRITICAL: failed to publish the exact candidate revert; refusing to guess at main"
      fi
    else
      notify ":rotating_light: candidate ${candidate_revision:0:8} failed soak, but main moved to ${remote_revision:0:8}; refusing to revert a manual commit"
    fi

    rollback_failed=0
    for host in alpha pi epsilon; do
      rollback_host=0
      if [ -e "$state/reached-$revision-$host" ]; then
        rollback_host=1
      else
        for deployed_host in "${deployed[@]}"; do
          if [ "$deployed_host" = "$host" ]; then
            rollback_host=1
            break
          fi
        done
      fi
      [ "$rollback_host" = 1 ] || continue
      before=$(cat "$state/before-$revision-$host" 2>/dev/null || true)
      if [[ "$before" != /nix/store/* ]] \
        && [[ "${before_generation[$host]-}" == /nix/store/* ]]; then
        before=${before_generation[$host]}
      fi
      if [ "$revert_published" = 1 ] && deploy ".#$host" --skip-checks; then
        continue
      fi
      if [[ "$before" != /nix/store/* ]] \
        || ! remote "$host" nix-env -p /nix/var/nix/profiles/system --set "$before" \
        || ! remote "$host" "$before/bin/switch-to-configuration" switch; then
        rollback_failed=1
      fi
    done
    if [ "$rollback_failed" = 1 ]; then
      notify ":rotating_light: fleet rollback after ${revision:0:8} needs operator review"
    else
      cleanup_candidate_roots "$revision"
    fi
  else
    for ((i = ${#deployed[@]} - 1; i >= 0; i--)); do
      host=${deployed[$i]}
      remote "$host" nix-env -p /nix/var/nix/profiles/system --set "${before_generation[$host]}" || true
      remote "$host" "${before_generation[$host]}/bin/switch-to-configuration" switch || true
    done
  fi

  notify ":rotating_light: fleet deployment failed at $failure_host (${revision:0:8}); rollback initiated, $streak consecutive$note"
  exit 1
fi

printf '0\n' > "$state/rollback-streak"
if [ "$requested_host" = all ]; then
  if [ "${#deferred[@]}" = 0 ]; then
    printf '%s\n' "$revision" > "$state/deployed-revision"
    if [ "$candidate_active" = 1 ]; then
      write_candidate "$candidate_revision" "$candidate_parent" completed
      cleanup_candidate_roots "$revision"
    fi
    notify ":white_check_mark: fleet converged on ${revision:0:8}"
  else
    notify ":information_source: required nodes converged on ${revision:0:8}; alpha remains deferred"
  fi
fi
