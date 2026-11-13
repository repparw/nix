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
      pkgs.python3
      pkgs.sqlite
    ]
  }
  test -d ${lib.escapeShellArg home}
  parent=${lib.escapeShellArg stateRoot}
  destination="$parent/offsite"
  seen_dir="$parent/.critical-seen"
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
  rsync --archive --relative --ignore-missing-args \
    ${lib.concatMapStringsSep " " (e: "--exclude=${lib.escapeShellArg e}") excludes} \
    -- \
    ${lib.escapeShellArgs (map (p: "${home}/./${p}") paths)} \
    "$temporary/"
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
  # A raw rsync copy is not a consistent SQLite snapshot when a writer
  # has an active WAL. Replace every detected SQLite file with a validated,
  # self-contained online snapshot before publishing the staging tree.
  python3 ${../scripts/home-state-sqlite.py} ${lib.escapeShellArg home} "$temporary"
  date --iso-8601=ns > "$temporary/.export-complete"
  rm -rf "$destination"
  mv "$temporary" "$destination"
''
