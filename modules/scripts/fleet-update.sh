# shellcheck shell=bash
usage="usage: fleet-update [--update-lock] [--host alpha|pi|epsilon] [--dry-activate] [--state DIR] [--source DIR]"

update_lock=0
dry_activate=0
requested_host=all
state="${FLEET_UPDATE_STATE:-/var/lib/fleet-update}"
source_repo="${FLEET_UPDATE_SOURCE:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --update-lock) update_lock=1 ;;
    --dry-activate) dry_activate=1 ;;
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
    --source)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      source_repo="$2"
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

if [ "$update_lock" = 1 ] && [ "$requested_host" != all ]; then
  echo "--update-lock always operates on the staged fleet" >&2
  exit 2
fi
if [ "$update_lock" = 1 ] && [ "$dry_activate" = 1 ]; then
  echo "--update-lock and --dry-activate cannot be combined" >&2
  exit 2
fi
if [ -n "$source_repo" ] && [ "$dry_activate" != 1 ]; then
  echo "--source is restricted to dry activation" >&2
  exit 2
fi

mkdir -p "$state"
exec 9>"${FLEET_UPDATE_LOCK:-/run/fleet-update.lock}"
if ! flock -n 9; then
  echo "another fleet update is already running"
  exit 0
fi

if [ -e "$state/PAUSE" ]; then
  echo "automation paused via $state/PAUSE"
  exit 0
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

if [ -n "$source_repo" ]; then
  repo=$(realpath "$source_repo")
else
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
    alpha) echo 192.168.0.18 ;;
    pi) echo 192.168.0.4 ;;
    epsilon) echo 146.181.42.97 ;;
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
  local host="$1"
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
        container@miniflux.service traefik.service || return 1
      http_code https://repparw.com/ 200 || return 1
      http_code https://rss.repparw.com/healthcheck 200 || return 1
      ;;
    pi)
      remote pi systemctl is-active --quiet \
        container@homeassistant.service container@archisteamfarm.service traefik.service || return 1
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
if [ "$(free_kb)" -lt $((10 * 1024 * 1024)) ]; then
  echo "below 10G on /nix; collecting old generations"
  nix-collect-garbage -d >/dev/null || true
fi
if [ "$(free_kb)" -lt $((6 * 1024 * 1024)) ]; then
  notify ":warning: fleet update aborted: $(df -h /nix | awk 'NR == 2 { print $4 }') free on /nix"
  exit 1
fi

candidate_created=0
if [ "$update_lock" = 1 ]; then
  if ! health_once pi; then
    notify ":warning: fleet update aborted: pi health gate is failing before the lock bump"
    exit 1
  fi

  timeout 20m systemctl start restic-backups-offsite.service ||
    notify ":information_source: fleet update proceeding without a fresh pi snapshot"

  nix flake update
  if ! git diff --exit-code flake.lock >/dev/null; then
    current_system=$(nix eval --impure --raw --expr builtins.currentSystem)
    nix build ".#checks.$current_system.deploy-schema" --no-link
    for host in epsilon pi alpha; do
      nix eval ".#nixosConfigurations.$host.config.system.build.toplevel.drvPath" --raw >/dev/null
    done

    git config user.name pi-auto-update
    git config user.email pi-auto-update@repparw.com
    git add flake.lock
    git commit -m "flake.lock: Update"
    export GIT_SSH_COMMAND="ssh -i $deploy_key -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    if ! git push git@github.com:repparw/nix.git HEAD:main; then
      notify ":warning: fleet update aborted: lock push failed; no host was changed"
      exit 1
    fi
    git push git@gitlab.com:repparw/nix.git HEAD:main ||
      notify ":warning: fleet update landed on GitHub but the GitLab mirror push failed"
    candidate_created=1
  else
    echo "lock unchanged; checking fleet convergence"
  fi
else
  current_system=$(nix eval --impure --raw --expr builtins.currentSystem)
  nix build ".#checks.$current_system.deploy-schema" --no-link
fi

revision=$(git rev-parse HEAD)
printf '%s\n' "$revision" > "$state/candidate-revision"

if [ "$requested_host" = all ]; then
  hosts=(epsilon pi alpha)
else
  hosts=("$requested_host")
fi

declare -A before_generation
deployed=()
deferred=()
failure_host=""

deploy_one() {
  local host="$1" running_revision before after_generation activity_gate

  running_revision=$(remote "$host" nixos-version --configuration-revision 2>/dev/null || true)
  if [ "$running_revision" = "$revision" ] && [ "$dry_activate" = 0 ]; then
    echo "$host already runs ${revision:0:8}"
    return 2
  fi

  activity_gate=$(nix eval --json ".#nixosConfigurations.$host.config.modules.fleet-update.activityGate") || return 1
  case "$activity_gate" in
    true)
      if ! host_is_idle "$host"; then
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
  deploy_args=(".#$host" --skip-checks)
  [ "$dry_activate" = 1 ] && deploy_args+=(--dry-activate)
  if ! deploy "${deploy_args[@]}"; then
    return 1
  fi
  [ "$dry_activate" = 1 ] && return 0

  deployed+=("$host")
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
  printf '%s\n' "$streak" > "$state/rollback-streak"
  note=""
  if [ "$streak" -ge 2 ]; then
    touch "$state/PAUSE"
    note=" — automation PAUSED (breaker)"
  fi

  if [ "$candidate_created" = 1 ]; then
    git revert --no-edit HEAD
    revert_revision=$(git rev-parse HEAD)
    git push git@github.com:repparw/nix.git HEAD:main ||
      notify ":rotating_light: CRITICAL: failed to push the fleet lock revert"
    git push git@gitlab.com:repparw/nix.git HEAD:main || true

    rollback_failed=0
    for ((i = ${#deployed[@]} - 1; i >= 0; i--)); do
      host=${deployed[$i]}
      if ! deploy ".#$host" --skip-checks; then
        rollback_failed=1
        remote "$host" nix-env -p /nix/var/nix/profiles/system --set "${before_generation[$host]}" || true
        remote "$host" "${before_generation[$host]}/bin/switch-to-configuration" switch || true
      fi
    done
    if [ "$rollback_failed" = 1 ]; then
      notify ":rotating_light: fleet rollback to ${revert_revision:0:8} needs operator help"
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

if [ "$dry_activate" = 0 ]; then
  printf '0\n' > "$state/rollback-streak"
  if [ "${#deferred[@]}" = 0 ]; then
    printf '%s\n' "$revision" > "$state/deployed-revision"
    notify ":white_check_mark: fleet converged on ${revision:0:8}"
  else
    notify ":information_source: required nodes converged on ${revision:0:8}; alpha remains deferred"
  fi
fi
