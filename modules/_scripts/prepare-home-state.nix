{
  pkgs,
  lib,
}:
{
  home,
  stateRoot,
  paths,
  excludes ? [ ],
}:
pkgs.writeShellScript "prepare-home-state" ''
  set -euo pipefail
  export PATH=${
    lib.makeBinPath [
      pkgs.coreutils
      pkgs.rsync
      pkgs.util-linux
      pkgs.python3
      pkgs.sqlite
    ]
  }
  test -d ${lib.escapeShellArg home}
  parent=${lib.escapeShellArg stateRoot}
  destination="$parent/offsite"
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

  mkdir -p "$temporary/.config" "$temporary/.local"
  if [ "''${1:-}" = --retry ]; then
    # Reuse the previous staging tree while retrying failed SQLite copies.
    cp -a --reflink=auto "$destination/." "$temporary/"
  else
  rsync --archive --relative --ignore-missing-args \
    ${lib.concatMapStringsSep " " (e: "--exclude=${lib.escapeShellArg e}") excludes} \
    -- \
    ${lib.escapeShellArgs (map (p: "${home}/./${p}") paths)} \
    "$temporary/"
  fi
  # Replace raw SQLite copies with verified, self-contained snapshots.
  if [ "''${1:-}" = --retry ]; then
    python3 ${../scripts/home-state-sqlite.py} --retry ${lib.escapeShellArg home} "$temporary"
  else
    python3 ${../scripts/home-state-sqlite.py} ${lib.escapeShellArg home} "$temporary" "$destination" ${lib.escapeShellArg (builtins.toJSON paths)}
  fi
  # A targeted retry still needs a full export before it may claim complete.
  if [ "''${1:-}" != --retry ] && [ ! -f "$temporary/.sqlite-retry-needed" ]; then
    date --iso-8601=ns > "$temporary/.export-complete"
  fi
  python3 ${../scripts/home-state-sqlite.py} --publish "$temporary" "$destination"
''
