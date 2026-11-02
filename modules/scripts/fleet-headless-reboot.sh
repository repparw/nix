# shellcheck shell=bash
# Sequentially reboot the headless fleet hosts into their staged
# kernel/initrd generations. fleet-update starts this best-effort right
# after a successful convergence, so a staged kernel lands within minutes
# instead of waiting for the nightly window; the 03:00 timer is the safety
# net for whatever a deploy deferred (busy backup), skipped (manual
# rebuild), or never triggered. Both paths enter the same
# flock-serialized sequence: epsilon first, then pi, each gated on backup
# state and post-reboot health.
#
# Exit codes: 0 = converged, deferred, or another fleet operation held the
# lock; 1 = the sequence failed and needs attention.
deploy_key="${FLEET_DEPLOY_KEY:-/home/repparw/.ssh/id_ed25519}"
if [ ! -r "$deploy_key" ]; then
  echo "deployment key is not readable: $deploy_key" >&2
  exit 1
fi

exec 9>"${FLEET_UPDATE_LOCK:-/run/fleet-update.lock}"
# fleet-update queues this service before exiting and releasing its flock.
# Wait briefly so the post-deploy check actually runs after lock release;
# fail visibly on timeout and let the nightly timer provide a retry.
if ! flock -w "${FLEET_REBOOT_LOCK_WAIT_SECONDS:-300}" 9; then
  echo "fleet-headless-reboot: fleet lock not released before timeout; nightly timer will retry" >&2
  exit 1
fi

epsilon="@FLEET_EPSILON_ADDRESS@"
ssh_options=(
  -i "$deploy_key"
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
)

remote_epsilon() {
  # Arguments are intentionally expanded by this client-side wrapper.
  # shellcheck disable=SC2029
  ssh "${ssh_options[@]}" "root@$epsilon" "$@"
}

# The predicate's own exit codes carry through ssh; a transport failure
# surfaces as 255, which the callers treat exactly like unknown state.
reboot_required_local() {
  fleet-reboot-required
}

reboot_required_epsilon() {
  remote_epsilon fleet-reboot-required
}

http_200() {
  [ "$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$1" || true)" = 200 ]
}

epsilon_healthy() {
  local state
  state=$(remote_epsilon systemctl is-system-running 2>/dev/null || true)
  case "$state" in
    running | degraded) ;;
    *) return 1 ;;
  esac
  # Container units derive from the service registry; traefik is
  # the native edge ingress and stays outside the container gate.
  remote_epsilon systemctl is-active --quiet \
    @FLEET_EPSILON_CONTAINERS@ traefik.service \
    || return 1
  http_200 @FLEET_APEX_URL@ || return 1
  http_200 @FLEET_MINIFLUX_HEALTH@ || return 1
}

backup_state_epsilon() {
  remote_epsilon systemctl is-active restic-backups-offsite.service 2>/dev/null || true
}

backup_state_local() {
  systemctl is-active restic-backups-offsite.service 2>/dev/null || true
}

backup_is_busy() {
  case "$1" in
    active | activating | reloading | deactivating) return 0 ;;
    inactive | failed) return 1 ;;
    *) return 2 ;;
  esac
}

wait_epsilon_reboot() {
  local old_boot_id="$1" boot_id passes=0
  # 20 minutes for a Pi-class host to come back over SSH; overridable so
  # the fixture test can exercise the timeout path.
  local deadline=$((SECONDS + ${FLEET_REBOOT_WAIT_SECONDS:-1200}))
  while [ "$SECONDS" -lt "$deadline" ]; do
    boot_id=$(remote_epsilon cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)
    if [ -n "$boot_id" ] && [ "$boot_id" != "$old_boot_id" ]; then
      if epsilon_healthy; then
        passes=$((passes + 1))
        if [ "$passes" -ge 2 ]; then
          return 0
        fi
      else
        passes=0
      fi
    fi
    sleep 15
  done
  return 1
}

epsilon_pending=0
if reboot_required_epsilon; then
  epsilon_pending=1
else
  rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "fleet-headless-reboot: cannot determine epsilon boot state; refusing sequence" >&2
    exit 1
  fi
fi

pi_pending=0
if reboot_required_local; then
  pi_pending=1
else
  rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "fleet-headless-reboot: cannot determine pi boot state; refusing sequence" >&2
    exit 1
  fi
fi

if [ "$epsilon_pending" -eq 0 ] && [ "$pi_pending" -eq 0 ]; then
  echo "fleet-headless-reboot: both headless hosts already converged"
  exit 0
fi

if [ "$epsilon_pending" -eq 1 ]; then
  epsilon_backup=$(backup_state_epsilon)
  if backup_is_busy "$epsilon_backup"; then
    echo "fleet-headless-reboot: epsilon backup is $epsilon_backup; deferring sequence"
    exit 0
  else
    rc=$?
    if [ "$rc" -ne 1 ]; then
      echo "fleet-headless-reboot: cannot determine epsilon backup state; refusing sequence" >&2
      exit 1
    fi
  fi

  old_boot_id=$(remote_epsilon cat /proc/sys/kernel/random/boot_id 2>/dev/null) || {
    echo "fleet-headless-reboot: cannot read epsilon boot id; refusing reboot" >&2
    exit 1
  }
  echo "fleet-headless-reboot: rebooting epsilon into staged kernel/initrd"
  discord-notify post ":arrows_counterclockwise: rebooting epsilon into the staged kernel/initrd" >/dev/null 2>&1 || true
  remote_epsilon systemctl reboot --no-block
  if ! wait_epsilon_reboot "$old_boot_id"; then
    echo "fleet-headless-reboot: epsilon did not return healthy after reboot; pi stays up" >&2
    exit 1
  fi
  if reboot_required_epsilon; then
    echo "fleet-headless-reboot: epsilon rebooted but is still on a mismatched kernel/initrd; pi stays up" >&2
    exit 1
  else
    rc=$?
    if [ "$rc" -ne 1 ]; then
      echo "fleet-headless-reboot: cannot verify epsilon convergence; pi stays up" >&2
      exit 1
    fi
  fi
fi

if [ "$pi_pending" -eq 0 ]; then
  echo "fleet-headless-reboot: pi already converged"
  exit 0
fi

if ! epsilon_healthy; then
  echo "fleet-headless-reboot: epsilon health gate is failing; pi stays up" >&2
  exit 1
fi

pi_backup=$(backup_state_local)
if backup_is_busy "$pi_backup"; then
  echo "fleet-headless-reboot: pi backup is $pi_backup; deferring pi reboot"
  exit 0
else
  rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "fleet-headless-reboot: cannot determine pi backup state; refusing reboot" >&2
    exit 1
  fi
fi

echo "fleet-headless-reboot: rebooting pi into staged kernel/initrd"
discord-notify post ":arrows_counterclockwise: rebooting pi into the staged kernel/initrd" >/dev/null 2>&1 || true
systemctl reboot --no-block

exec sleep infinity
