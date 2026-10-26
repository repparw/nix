# Builder for Alpha's home-state staging script (consumed by hosts/alpha.nix).
# Parameterized so the home-state-backup check can exercise the exact
# production script against a fixture home. Lives under _scripts/ so
# import-tree does not treat it as a module.
{
  pkgs,
  lib,
}:
{
  # Absolute home and staging root; both are baked into the script.
  home,
  stateRoot,
  # Home-relative paths staged for both destinations.
  paths,
  # Rsync exclude patterns applied below the --relative anchor.
  excludes ? [ ],
  # Paths staged only for the HDD destination (never uploaded offsite).
  hddOnlyPaths ? [ ],
  # Subset of paths guarded as critical: when a source exists it must be
  # unlocked by OpenTofu, staged non-empty, and parseable, or the whole
  # export fails and the previous staged generation is preserved. A missing
  # source is tolerated so hosts without the feature still back up.
  criticalPaths ? [ ],
}:
pkgs.writeShellScript "prepare-home-state" ''
  set -euo pipefail
  export PATH=${
    lib.makeBinPath [
      pkgs.coreutils
      pkgs.jq
      pkgs.rsync
    ]
  }
  test -d ${lib.escapeShellArg home}
  case "$1" in hdd|offsite) ;; *) exit 1 ;; esac
  parent=${lib.escapeShellArg stateRoot}
  destination="$parent/$1"
  temporary=$(mktemp -d "$parent/.prepare-$1.XXXXXX")
  trap 'rm -rf "$temporary"' EXIT
  mkdir -p "$temporary/.config" "$temporary/.local"
  ${lib.concatMapStrings (path: ''
    # Critical source lock guard: ${path}
    critical_source=${lib.escapeShellArg "${home}/${path}"}
    if [ -e "$critical_source" ]; then
      critical_lock="$(dirname "$critical_source")/.$(basename "$critical_source").lock.info"
      if [ -e "$critical_lock" ]; then
        printf 'home-state: %s exists; OpenTofu holds the state lock, retry once it finishes\n' "$critical_lock" >&2
        exit 1
      fi
    fi
  '') criticalPaths}
  rsync --archive --relative --ignore-missing-args \
    ${lib.concatMapStringsSep " " (e: "--exclude=${lib.escapeShellArg e}") excludes} \
    -- \
    ${lib.escapeShellArgs (map (p: "${home}/./${p}") paths)} \
    "$temporary/"
  ${lib.concatMapStrings (path: ''
    # Critical staged validation: ${path}
    critical_source=${lib.escapeShellArg "${home}/${path}"}
    if [ -e "$critical_source" ]; then
      critical_staged="$temporary"/${lib.escapeShellArg path}
      if [ ! -s "$critical_staged" ]; then
        printf 'home-state: %s exists but produced no staged copy\n' "$critical_source" >&2
        exit 1
      fi
      jq -e '(.version | type == "number") and (.serial | type == "number") and (.resources | type == "array")' \
        "$critical_staged" >/dev/null ||
        {
          printf 'home-state: staged %s is not a parseable OpenTofu state\n' "$critical_staged" >&2
          exit 1
        }
    fi
  '') criticalPaths}
  if [ "$1" = hdd ]; then
    rsync --archive --relative --ignore-missing-args -- \
      ${lib.escapeShellArgs (map (p: "${home}/./${p}") hddOnlyPaths)} \
      "$temporary/"
  fi
  date --iso-8601=ns > "$temporary/.export-complete"
  rm -rf "$destination"
  mv "$temporary" "$destination"
''
