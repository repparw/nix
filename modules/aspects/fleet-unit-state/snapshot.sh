# shellcheck shell=bash
state_dir="${FLEET_UNIT_STATE_DIRECTORY:-/var/lib/fleet-unit-state}"
test -d "$state_dir"
current=$(systemctl list-units --state=failed --all --plain --no-legend --no-pager)
{
  printf '%s\n' "$current" | awk 'NF {print $1}'
  find "$state_dir" -maxdepth 1 -type f ! -name '.*' -printf '%f\n'
} | LC_ALL=C sort -u
