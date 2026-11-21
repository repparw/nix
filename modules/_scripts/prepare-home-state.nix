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
  # Restic holds this lock shared throughout backup; publish exclusively.
  exec 9>"$parent/.stage.lock"
  flock --exclusive 9
  temporary=$(mktemp -d "$parent/.prepare-offsite.XXXXXX")
  trap 'rm -rf "$temporary"' EXIT
  mkdir -p "$temporary/.config" "$temporary/.local"
  rsync --archive --relative --ignore-missing-args \
    ${lib.concatMapStringsSep " " (e: "--exclude=${lib.escapeShellArg e}") excludes} \
    -- \
    ${lib.escapeShellArgs (map (p: "${home}/./${p}") paths)} \
    "$temporary/"
  python3 ${../scripts/home-state-sqlite.py} ${lib.escapeShellArg home} "$temporary" "$destination" ${lib.escapeShellArg (builtins.toJSON paths)}
  python3 ${../scripts/home-state-sqlite.py} --publish "$temporary" "$destination"
''
