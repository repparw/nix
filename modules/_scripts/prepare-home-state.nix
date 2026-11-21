{
  pkgs,
  lib,
}:
{
  home,
  stateRoot,
  paths,
  excludes ? [ ],
  criticalPaths ? [ ],
}:
let
  markerOf = path: builtins.replaceStrings [ "/" ] [ "__" ] path;
in
pkgs.writeShellScript "prepare-home-state" ''
  set -euo pipefail
  export PATH=${
    lib.makeBinPath [
      pkgs.coreutils
      pkgs.jq
      pkgs.rsync
      pkgs.util-linux
      pkgs.python3
      pkgs.sqlite
    ]
  }
  test -d ${lib.escapeShellArg home}
  parent=${lib.escapeShellArg stateRoot}
  destination="$parent/offsite"
  seen_dir="$parent/.critical-seen"
  # Restic holds this same lock in shared mode for its entire backup.
  # A retry skips without error if a backup owns the lock.
  exec 9>"$parent/.stage.lock"
  if [ "''${1:-}" = --retry ]; then
    if ! flock --exclusive --nonblock 9; then
      printf 'home-state: Restic or staging is active; retry deferred\n' >&2
      exit 0
    fi
  else
    flock --exclusive 9
  fi
  temporary=$(mktemp -d "$parent/.prepare-offsite.XXXXXX")
  trap 'rm -rf "$temporary"' EXIT

  mkdir -p "$temporary/.config" "$temporary/.local" "$seen_dir"
  ${lib.concatMapStrings (path: ''
    critical_source=${lib.escapeShellArg "${home}/${path}"}
    if [ -e "$critical_source" ]; then
      critical_lock="$(dirname "$critical_source")/.$(basename "$critical_source").lock.info"
      if [ -e "$critical_lock" ]; then
        printf 'home-state: %s exists; OpenTofu holds the state lock, retry once it finishes\n' "$critical_lock" >&2
        exit 1
      fi
    elif [ -e "$seen_dir/${markerOf path}" ]; then
      printf 'home-state: %s was backed up before but is now missing; not publishing a generation without it\n' "$critical_source" >&2
      exit 1
    fi
  '') criticalPaths}
  if [ "''${1:-}" = --retry ]; then
    # Reuse the verified staging tree and refresh critical state too.
    cp -a --reflink=auto "$destination/." "$temporary/"
    ${lib.optionalString (criticalPaths != [ ]) ''
      rsync --archive --relative --ignore-missing-args -- \
        ${lib.escapeShellArgs (map (p: "${home}/./${p}") criticalPaths)} \
        "$temporary/"
    ''}
  else
  rsync --archive --relative --ignore-missing-args \
    ${lib.concatMapStringsSep " " (e: "--exclude=${lib.escapeShellArg e}") excludes} \
    -- \
    ${lib.escapeShellArgs (map (p: "${home}/./${p}") paths)} \
    "$temporary/"
  fi
  ${lib.concatMapStrings (path: ''
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
      printf '%s\n' "$(date --iso-8601=ns)" > "$seen_dir/${markerOf path}"
    fi
  '') criticalPaths}
  # Replace raw SQLite copies with verified, self-contained snapshots.
  if [ "''${1:-}" = --retry ]; then
    python3 ${../scripts/home-state-sqlite.py} --retry ${lib.escapeShellArg home} "$temporary"
  else
    python3 ${../scripts/home-state-sqlite.py} ${lib.escapeShellArg home} "$temporary" "$destination"
  fi
  # A targeted retry still needs a full export before it may claim complete.
  if [ "''${1:-}" != --retry ] && [ ! -f "$temporary/.sqlite-retry-needed" ]; then
    date --iso-8601=ns > "$temporary/.export-complete"
  fi
  python3 ${../scripts/home-state-sqlite.py} --publish "$temporary" "$destination"
''
