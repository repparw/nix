# shellcheck shell=bash
unit="$1"
state_dir="${FLEET_UNIT_STATE_DIRECTORY:-/var/lib/fleet-unit-state}"
mkdir -p "$state_dir"
if [ "${SERVICE_RESULT:-}" = success ]; then
  rm -f -- "$state_dir/$unit"
else
  temporary=$(mktemp "$state_dir/.result.XXXXXX")
  printf '%s %s\n' "$(date --iso-8601=seconds)" "${SERVICE_RESULT:-unknown}" > "$temporary"
  mv -f -- "$temporary" "$state_dir/$unit"
fi
