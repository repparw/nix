# shellcheck shell=bash
# Exit 0 when a staged kernel, kernel modules or initrd differs from the
# running boot (reboot pending), 1 when both sides match (converged), and 2
# when either side cannot be determined. The same predicate as
# system.autoUpgrade.allowReboot: switch-to-configuration already activated
# userspace, so only the boot chain decides whether a reboot is owed.
#
# This file is the single implementation behind every caller: the health
# collector (fleet_reboot_required metric), the headless reboot sequence,
# and fleet debug.
usage="usage: fleet-reboot-required [--booted DIR] [--staged DIR]"

booted=/run/booted-system
staged=/nix/var/nix/profiles/system

while [ "$#" -gt 0 ]; do
  case "$1" in
    --booted)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      booted="$2"
      shift 2
      ;;
    --staged)
      [ "$#" -ge 2 ] || { echo "$usage" >&2; exit 2; }
      staged="$2"
      shift 2
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
done

# Existence is checked before readlink so a missing link reports unknown
# state (2) instead of comparing two literal paths that never match.
for root in "$booted" "$staged"; do
  for name in initrd kernel kernel-modules; do
    if [ ! -e "$root/$name" ]; then
      echo "fleet-reboot-required: missing $root/$name" >&2
      exit 2
    fi
  done
done

# Compare resolved targets, not generation names: both sides point at the
# same store paths while converged regardless of their link names.
for name in initrd kernel kernel-modules; do
  if [ "$(readlink -f "$booted/$name")" != "$(readlink -f "$staged/$name")" ]; then
    exit 0
  fi
done
exit 1
