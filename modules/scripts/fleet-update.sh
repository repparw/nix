# shellcheck shell=bash
usage="usage: fleet-update deploy [--host all|alpha|pi|epsilon] [--force] [--wait-lock SECONDS] [--state DIR]"

[ "$#" -gt 0 ] || { echo "$usage" >&2; exit 2; }
action="$1"
shift
case "$action" in
  deploy) ;;
  *) echo "$usage" >&2; exit 2 ;;
esac

force=0
lock_wait=0
requested_host=all
host_selected=0
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
      host_selected=1
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

if [ "$force" = 1 ] && [ "$host_selected" = 0 ]; then
  echo "--force requires an explicit --host" >&2
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

api="https://discord.com/api/v10/channels/@FLEET_DISCORD_CHANNEL@/messages"
notify() {
  [ -r /run/secrets/hermes-env ] || return 0
  # shellcheck disable=SC1091
  source /run/secrets/hermes-env
  curl -sS -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg c "$1" '{content: $c}')" "$api" >/dev/null || true
}

# nix store diff-closures emits ANSI color codes even when piped (verified:
# `nix store diff-closures a b | cat -v` shows ^[[31;1m). Discord eats the
# ESC byte and renders the bare `[31;1m` fragments, so scrub control
# sequences before the diff reaches a message or an attachment.
strip_ansi() {
  awk 'BEGIN { esc = sprintf("%c", 27) } { gsub(esc "\\[[0-9;?]*[A-Za-z]", ""); gsub(/\r/, ""); print }'
}

# Why the current transaction is failing, in one line, for the rollback
# notification. Set by fail() and by health_once() so a soak failure names the
# probe that broke rather than just the host.
failure_reason=""

fail() {
  failure_reason="$1"
  echo "$1" >&2
  return 1
}

# A failure is only actionable with the failing command's own output, and the
# transient deploy unit's journal does not survive the controller rebooting.
# Post the best single explanation available and attach the log when the
# explanation had to be truncated to fit.
notify_failure() {
  [ -r /run/secrets/hermes-env ] || return 0
  local header="$1" log="$2" budget=1200 fence detail body sanitized detail_units
  local -a attachment=()
  # shellcheck disable=SC1091
  source /run/secrets/hermes-env
  # Built in double quotes: shellcheck reads backticks in single quotes
  # as command substitution that will never expand (SC2016).
  fence="\`\`\`"

  # A soak failure is fully described by the probe that broke, and the log it
  # would otherwise quote is the activation that just succeeded. A build
  # failure is described by its own output, which already names the host. So
  # pick one, never both: the reason only appears when it is the better story.
  detail=""
  case "$failure_reason" in
    soak:*) detail=$failure_reason ;;
  esac
  if [[ "$failure_reason" == "build or activation of "* || "$failure_reason" == "preparation of "* ]] && [ -s "$log" ]; then
    # nix ends a failed build with a cascade of "Cannot build ... Reason: N
    # dependencies failed" and buries the compiler or evaluator error that
    # actually explains it in the middle, so take the lines naming a failure.
    sanitized=$(strip_ansi <"$log")
    # Read the whole stream: grep|head can fail with SIGPIPE under pipefail,
    # and grep's no-match status must not abort the rollback notification.
    detail=$(printf '%s\n' "$sanitized" | awk '
      /error:|FAILED:|Reason:|build stopped/ { if (++matches <= 25) print }
    ')
  fi
  [ -n "$detail" ] || detail=$failure_reason
  [ -n "$detail" ] || detail="no reason recorded; see the attached log"
  # Discord renders a bare backtick as markup start, so neutralise it.
  detail=${detail//\`/\'}

  # Count UTF-16 units, including two units for supplementary characters.
  # Discord's limit includes the header and code fences.
  budget=$(jq -n --arg h "$header" '
    2000 - ($h | explode | map(if . > 65535 then 2 else 1 end) | add // 0) - 80
    | if . < 0 then 0 elif . > 1200 then 1200 else . end
  ')
  detail_units=$(printf '%s' "$detail" | jq -Rs '
    explode | map(if . > 65535 then 2 else 1 end) | add // 0
  ')
  if [ "$detail_units" -le "$budget" ]; then
    body=$(printf '%s\n%swhat failed\n%s\n%s' \
      "$header" "$fence" "$detail" "$fence")
    curl -sS -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg c "$body" '{content: $c}')" "$api" >/dev/null || true
    return 0
  fi
  detail=$(printf '%s' "$detail" | jq -Rs -r --argjson n "$budget" '
    reduce explode[] as $c ({units: 0, chars: [], full: false};
      ($c | if . > 65535 then 2 else 1 end) as $width
      | if .full or .units + $width > $n then .full = true
        else .units += $width | .chars += [$c] end
    ) | .chars | implode
  ')
  # Prefer complete lines when available, but keep a long single-line error.
  if [[ "$detail" == *$'\n'* ]]; then detail=${detail%$'\n'*}; fi
  if [ -s "$log" ]; then
    body=$(printf '%s\n%swhat failed\n%s\n%s\n(full output attached)' \
      "$header" "$fence" "$detail" "$fence")
    attachment=(-F "files[0]=@$log")
    curl -sS -m 30 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
      -F "payload_json=$(jq -n --arg c "$body" '{content: $c}')" \
      "${attachment[@]}" "$api" >/dev/null || true
  else
    body=$(printf '%s\n%swhat failed\n%s\n%s\n(detail truncated)' \
      "$header" "$fence" "$detail" "$fence")
    curl -sS -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg c "$body" '{content: $c}')" "$api" >/dev/null || true
  fi
}

notify_file() {
  [ -r /run/secrets/hermes-env ] || return 0
  [ -s "$2" ] || return 0
  # shellcheck disable=SC1091
  source /run/secrets/hermes-env
  # Discord caps content at 2000 chars and has no collapsible code blocks.
  header="$1"
  file="$2"
  budget=1600
  # Built in double quotes: shellcheck reads backticks in single quotes
  # as command substitution that will never expand (SC2016).
  fence="\`\`\`"
  raw=$(<"$file")
  sanitized=${raw//\`/\'}
  summaries=$(printf '%s' "$sanitized" | awk '/→/')
  if [ -n "$summaries" ]; then
    inline=$summaries
  else
    inline=$sanitized
  fi
  if [ "${#inline}" -gt "$budget" ]; then
    # jq slices by characters, so multibyte output (nix's → arrows)
    # is never split mid-codepoint the way head -c would split it.
    snippet=$(printf '%s' "$inline" | jq -Rs -r --argjson n "$budget" '.[0:$n]')
    body=$(printf '%s\n%sdiff\n%s\n%s\n(full diff attached)' "$header" "$fence" "$snippet" "$fence")
    curl -sS -m 30 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
      -F "payload_json=$(jq -n --arg c "$body" '{content: $c}')" \
      -F "files[0]=@$file" "$api" >/dev/null || true
  else
    body=$(printf '%s\n%sdiff\n%s\n%s' "$header" "$fence" "$inline" "$fence")
    curl -sS -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg c "$body" '{content: $c}')" "$api" >/dev/null || true
  fi
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

remote() {
  local host="$1"
  shift
  # Arguments are intentionally expanded by this client-side wrapper.
  # shellcheck disable=SC2029
  ssh "${ssh_options[@]}" "root@$(host_address "$host")" "$@"
}

host_is_idle() {
  local host="$1" inhibitors blocking_sleep

  # A locked physical session can still be serving an active remote game or
  # media stream. Those applications publish the standard systemd sleep
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

# Container units owned by a host, derived from the service registry of the
# deployed revision (definitions with container = true) instead of a
# hardcoded list, so the soak gate cannot drift when services move between
# hosts. Evaluated once per host per run and cached; the raw JSON stays in
# the cache so a legitimately empty list is not re-evaluated.
declare -A container_units_json
container_units() { # host -> space-separated container@name units; 1 on eval failure
  local host="$1"
  if [ -z "${container_units_json[$host]-}" ]; then
    container_units_json[$host]=$(nix eval --json ".#nixosConfigurations.$host.config.modules.fleet-update.containerUnits") || return 1
  fi
  jq -r 'join(" ")' <<< "${container_units_json[$host]}"
}

health_once() {
  local host="$1" state_now units unit unit_state
  state_now=$(remote "$host" systemctl is-system-running 2>/dev/null || true)
  case "$state_now" in
    running | degraded) ;;
    *)
      fail "soak: $host is-system-running is ${state_now:-unreachable}"
      return 1
      ;;
  esac

  if ! units=$(container_units "$host"); then
    fail "soak: could not evaluate the container unit list for $host"
    return 1
  fi
  if [ -n "$units" ]; then
    # Unit names are intentionally expanded by this client-side wrapper.
    # shellcheck disable=SC2086,SC2029
    if ! remote "$host" systemctl is-active --quiet $units; then
      for unit in $units; do
        # systemctl prints the state on stdout and exits non-zero for a unit
        # that is not active, so take the first line and ignore the status.
        # shellcheck disable=SC2029
        unit_state=$(remote "$host" systemctl is-active "$unit" 2>/dev/null | head -1) || true
        [ "$unit_state" = active ] && continue
        fail "soak: $unit is ${unit_state:-unreachable} on $host"
        return 1
      done
      fail "soak: a container unit on $host is not active"
      return 1
    fi
  fi
  # The native edge ingress is not a container; it stays outside the
  # derived container gate.
  case "$host" in
    epsilon | pi)
      if ! remote "$host" systemctl is-active --quiet traefik.service; then
        fail "soak: traefik.service is not active on $host"
        return 1
      fi
      ;;
  esac

  case "$host" in
    epsilon)
      http_code https://@FLEET_DOMAIN@/ 200 ||
        {
          fail "soak: https://@FLEET_DOMAIN@/ on $host did not return 200"
          return 1
        }
      http_code https://rss.@FLEET_DOMAIN@/healthcheck 200 ||
        {
          fail "soak: rss healthcheck on $host did not return 200"
          return 1
        }
      ;;
    pi)
      http_code https://home.@FLEET_DOMAIN@/ 200 ||
        {
          fail "soak: https://home.@FLEET_DOMAIN@/ on $host did not return 200"
          return 1
        }
      ;;
    alpha)
      http_code http://@FLEET_ALPHA_ADDRESS@:8096/health 200 ||
        {
          fail "soak: jellyfin health on $host did not return 200"
          return 1
        }
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

cleanup_rollback_roots() {
  local host
  for host in epsilon pi alpha; do
    if remote "$host" rm -f "/nix/var/nix/gcroots/fleet-update/previous" 2>/dev/null; then
      rm -f "$state/reached-$revision-$host"
    fi
  done
}

ci_passed() {
  local runs
  runs=$(curl --fail --silent --show-error --max-time 30 \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "https://api.github.com/repos/repparw/nix/actions/workflows/ci.yml/runs?head_sha=$revision&per_page=100") || return 1
  jq -e --arg revision "$revision" '
    [.workflow_runs[]
      | select(
          .head_sha == $revision
          and (
            (.event == "push" and .head_branch == "main")
            or (
              .event == "workflow_dispatch"
              and (.head_branch == "main" or .head_branch == "automation/flake-lock")
            )
          )
        )]
    | sort_by(.run_number) | last
    | .status == "completed" and .conclusion == "success"
  ' <<< "$runs" >/dev/null
}

capture_host() {
  local host="$1" drv roots="${FLEET_UPDATE_ROOTS:-/nix/var/nix/gcroots/fleet-update}"
  nix eval --json --no-update-lock-file --expr "
    let f = builtins.getFlake \"$source\";
        c = f.nixosConfigurations.$host.config;
        n = f.deploy.nodes.$host;
    in {
      revision = c.system.configurationRevision;
      systemPath = c.system.build.toplevel.outPath;
      activityGate = c.modules.fleet-update.activityGate;
      containerUnits = c.modules.fleet-update.containerUnits;
      deployment = f.deploy // { nodes = {
        $host = n // { profiles.system = n.profiles.system // {
          path = n.profiles.system.path.outPath;
          drvPath = n.profiles.system.path.drvPath;
        }; };
      }; };
    }" > "$preparation/$host.json" || return 1
  jq -e --arg revision "$revision" --arg host "$host" '
    .revision == $revision
    and (.systemPath | test("^/nix/store/[A-Za-z0-9+._=-]+$"))
    and (.activityGate | type == "boolean")
    and (.containerUnits | type == "array")
    and (.deployment.nodes[$host].profiles.system.path | test("^/nix/store/[A-Za-z0-9+._=-]+$"))
    and (.deployment.nodes[$host].profiles.system.drvPath | test("^/nix/store/[A-Za-z0-9+._=-]+\\.drv$"))
  ' "$preparation/$host.json" >/dev/null || {
    echo "error: captured metadata for $host is invalid or has a different revision than $revision" >&2
    return 1
  }
  drv=$(jq -r --arg host "$host" '.deployment.nodes[$host].profiles.system.drvPath' "$preparation/$host.json")
  mkdir -p "$roots" || return 1
  ln -sfn "$drv" "$roots/derivation-$host" || return 1
  jq --arg host "$host" '{host: $host, revision, systemPath,
    profilePath: .deployment.nodes[$host].profiles.system.path, outcome: "not_attempted"}' \
    "$preparation/$host.json" > "$preparation/result-$host.json"
}

capture_hosts() {
  local host
  for host in "${hosts[@]}"; do
    if ! capture_host "$host" > "$preparation/capture-$host.log" 2>&1; then
      jq '.outcome = "failed" | .stage = "capture"' "$preparation/result-$host.json" \
        > "$preparation/result-$host.tmp"
      mv "$preparation/result-$host.tmp" "$preparation/result-$host.json"
      cat "$preparation/capture-$host.log"
      return 1
    fi
  done
}

prepare_host() {
  local host="$1" drv profile system built observed store
  drv=$(jq -r --arg host "$host" '.deployment.nodes[$host].profiles.system.drvPath' "$preparation/$host.json")
  profile=$(jq -r --arg host "$host" '.deployment.nodes[$host].profiles.system.path' "$preparation/$host.json")
  system=$(jq -r '.systemPath' "$preparation/$host.json")
  store="ssh-ng://root@$(host_address "$host")"
  NIX_SSHOPTS="${ssh_options[*]}" nix copy -s --to "$store" --derivation "$drv" || return 1
  remote "$host" mkdir -p /nix/var/nix/gcroots/fleet-update || return 1
  built=$(remote "$host" nix build "$drv^out" --out-link /nix/var/nix/gcroots/fleet-update/prepared --print-out-paths) || return 1
  [ "$built" = "$profile" ] || { echo "error: $host prepared unexpected profile: $built" >&2; return 1; }
  remote "$host" test -f "$profile/activate-rs" || return 1
  remote "$host" test -f "$profile/deploy-rs-activate" || return 1
  observed=$(remote "$host" "$system/sw/bin/nixos-version" --configuration-revision) || return 1
  jq -n --arg host "$host" --arg revision "$observed" --arg systemPath "$system" \
    --arg profilePath "$built" --arg outcome prepared \
    '{host: $host, revision: $revision, systemPath: $systemPath, profilePath: $profilePath, outcome: $outcome}' \
    > "$preparation/result-$host.json"
  [ "$observed" = "$revision" ] || { echo "error: $host prepared revision $observed, expected $revision" >&2; return 1; }
  jq '.deployment' "$preparation/$host.json" > "$preparation/$host/deploy.json"
  printf '%s\n' '{ outputs = { self }: { deploy = builtins.fromJSON (builtins.readFile ./deploy.json); }; }' \
    > "$preparation/$host/flake.nix"
}

if [ "$requested_host" = all ]; then
  hosts=(epsilon alpha pi)
else
  hosts=("$requested_host")
fi

revision=$(git rev-parse HEAD)
source="git+file://$repo?rev=$revision"
if ! ci_passed; then
  notify ":warning: fleet deployment deferred: CI has not passed for main ${revision:0:8}"
  echo "CI has not passed for main $revision; no host was changed" >&2
  exit 1
fi
printf '%s\n' "$revision" > "$state/target-revision"

current_system=$(nix eval --impure --raw --expr builtins.currentSystem)
preparation=$(mktemp -d "$state/preparation-$revision.XXXXXX")
printf '%s\n' "$preparation" > "$state/latest-preparation"
for host in "${hosts[@]}"; do
  jq -n --arg host "$host" --arg revision "$revision" \
    '{host: $host, revision: $revision, systemPath: null, profilePath: null, outcome: "not_attempted"}' \
    > "$preparation/result-$host.json"
done
preflight_log="$state/preflight.log"
if ! nix build ".#checks.$current_system.deploy-schema" --no-link > "$preflight_log" 2>&1 \
  || ! capture_hosts >> "$preflight_log" 2>&1; then
  failure_reason="deployment preflight failed"
  notify_failure ":warning: fleet deployment aborted before activation (${revision:0:8})" "$preflight_log"
  exit 1
fi

for host in "${hosts[@]}"; do
  # Each captured deployment has its own flake, so activation never rereads main.
  mkdir -p "$preparation/$host"
  if ! prepare_host "$host" > "$preparation/prepare-$host.log" 2>&1; then
    jq '.outcome = "failed"' "$preparation/result-$host.json" > "$preparation/result-$host.tmp"
    mv "$preparation/result-$host.tmp" "$preparation/result-$host.json"
    failure_reason="preparation of $host failed"
    streak=$(( $(cat "$state/rollback-streak" 2>/dev/null || echo 0) + 1 ))
    printf '%s\n' "$streak" > "$state/rollback-streak"
    touch "$state/PAUSE"
    notify_failure ":warning: fleet preparation failed at $host (${revision:0:8}); no activation started; automation PAUSED" "$preparation/prepare-$host.log"
    exit 1
  fi
  container_units_json[$host]=$(jq -c '.containerUnits' "$preparation/$host.json")
done

declare -A before_generation
deferred=()
failure_host=""
# One log per host, overwritten each run, so the evidence for the failure being
# reported is the evidence for that failure rather than a stale earlier one.
failure_log=""
for host in epsilon pi alpha; do rm -f "$state/fail-$host.log"; done

deploy_one() {
  local host="$1" running_revision before saved_before after_generation activity_gate
  failure_log="$state/fail-$host.log"
  failure_reason=""

  # Clear any stale diff so the failure report below never posts a
  # previous revision's diff for this host.
  rm -f "$state/diff-$host.txt"

  running_revision=$(remote "$host" nixos-version --configuration-revision 2>/dev/null || true)
  if [ "$running_revision" = "$revision" ]; then
    echo "$host already runs ${revision:0:8}"
    if ! soak "$host"; then
      fail "${failure_reason:-soak: $host never passed two consecutive health checks}"
      return 1
    fi
    return 2
  fi

  activity_gate=$(jq -r '.activityGate' "$preparation/$host.json") || {
    fail "could not evaluate the activity gate for $host"
    return 1
  }
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
      fail "$host returned an invalid activity-gate value: $activity_gate"
      return 1
      ;;
  esac

  before=$(remote "$host" readlink /run/current-system) || {
    fail "could not read the current system generation on $host"
    return 1
  }
  if [[ "$before" != /nix/store/* ]]; then
    fail "$host returned an invalid current-system path: ${before:-empty}"
    return 1
  fi
  saved_before=$(cat "$state/before-$revision-$host" 2>/dev/null || true)
  if [ -e "$state/reached-$revision-$host" ] && [[ "$saved_before" == /nix/store/* ]]; then
    before=$saved_before
  fi
  before_generation["$host"]=$before
  printf '%s\n' "$before" > "$state/before-$revision-$host" || return 1
  remote "$host" mkdir -p /nix/var/nix/gcroots/fleet-update || {
    fail "could not create rollback roots on $host"
    return 1
  }
  remote "$host" ln -sfn "$before" "/nix/var/nix/gcroots/fleet-update/previous" || {
    fail "could not pin the rollback generation on $host"
    return 1
  }
  touch "$state/reached-$revision-$host" || return 1
  # The build and activation output is the only record of why this failed, and
  # it has to outlive the transient unit, so keep it beside the other state.
  # pipefail propagates deploy-rs' own status through tee.
  if ! deploy "$preparation/$host#$host" --skip-checks 2>&1 | tee "$failure_log"; then
    fail "build or activation of $host failed"
    return 1
  fi

  running_revision=$(remote "$host" nixos-version --configuration-revision 2>/dev/null || true)
  if [ "$running_revision" != "$revision" ]; then
    fail "$host activated revision ${running_revision:-unknown}, expected $revision"
    return 1
  fi
  if ! soak "$host"; then
    fail "${failure_reason:-soak: $host never passed two consecutive health checks}"
    return 1
  fi

  after_generation=$(remote "$host" readlink /run/current-system)
  remote "$host" nix store diff-closures "${before_generation[$host]}" "$after_generation" \
    > "$state/diff-$host.txt" || true
  if [ -s "$state/diff-$host.txt" ]; then
    strip_ansi < "$state/diff-$host.txt" > "$state/diff-$host.tmp" \
      && mv "$state/diff-$host.tmp" "$state/diff-$host.txt"
  fi
  # Per-host success posts were channel noise: the diff stays on disk for
  # the failure report below, and the converged one-liner is the only
  # success signal. Diffs surface on failure only.
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
  # Preserve the existing breaker policy: soak failures allow one retry;
  # other deployment failures pause on the first cycle.
  case "$failure_reason" in
    soak:*) trip=2 ;;
    *) trip=1 ;;
  esac
  streak=$(( $(cat "$state/rollback-streak" 2>/dev/null || echo 0) + 1 ))
  printf '%s\n' "$streak" > "$state/rollback-streak" \
    || notify ":warning: could not persist the fleet rollback streak"
  note=""
  if [ "$streak" -ge "$trip" ]; then
    if touch "$state/PAUSE"; then
      note=" — automation PAUSED (breaker)"
    else
      note=" — WARNING: failed to persist the automation pause"
    fi
  fi

  rollback_failed=0
  for host in pi alpha epsilon; do
    [ -e "$state/reached-$revision-$host" ] || continue
    before=$(cat "$state/before-$revision-$host" 2>/dev/null || true)
    if [[ "$before" != /nix/store/* ]] \
      || ! remote "$host" nix-env -p /nix/var/nix/profiles/system --set "$before" \
      || ! remote "$host" "$before/bin/switch-to-configuration" switch \
      || [ "$(remote "$host" readlink /run/current-system 2>/dev/null || true)" != "$before" ]; then
      rollback_failed=1
    fi
  done
  if [ "$rollback_failed" = 1 ]; then
    touch "$state/PAUSE" || true
    notify ":rotating_light: fleet rollback after ${revision:0:8} needs operator review; rollback roots retained"
  else
    cleanup_rollback_roots
  fi

  # The reason and the failing command's own output first, then the closure
  # diff when the host got far enough to have one. A build failure clears the
  # diff, so a broken build posts only the error.
  notify_failure ":rotating_light: fleet deployment failed at $failure_host (${revision:0:8}); rollback initiated, $streak consecutive$note" \
    "$failure_log"
  notify_file ":rotating_light: diff for failed host $failure_host (${revision:0:8})" "$state/diff-$failure_host.txt"
  exit 1
fi

printf '0\n' > "$state/rollback-streak"
if [ "$requested_host" = all ]; then
  if [ "${#deferred[@]}" = 0 ]; then
    printf '%s\n' "$revision" > "$state/deployed-revision"
    cleanup_rollback_roots
    notify ":white_check_mark: fleet converged on ${revision:0:8}"
  else
    notify ":information_source: required nodes converged on ${revision:0:8}; alpha remains deferred"
  fi
fi
