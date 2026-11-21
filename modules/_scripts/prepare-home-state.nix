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
      pkgs.util-linux
      pkgs.python3
      pkgs.sqlite
    ]
  }
  test -d ${lib.escapeShellArg home}
  parent=${lib.escapeShellArg stateRoot}
  destination="$parent/offsite"
  # Restic holds this lock shared while reading the SQLite snapshots.
  exec 9>"$parent/.stage.lock"
  flock --exclusive 9
  temporary=$(mktemp -d "$parent/.prepare-offsite.XXXXXX")
  trap 'rm -rf "$temporary"' EXIT
  # The stage contains only verified SQLite snapshots, a manifest, and
  # a NUL-delimited list of ordinary files Restic backs up in place.
  python3 ${../scripts/home-state-sqlite.py} ${lib.escapeShellArg home} "$temporary" "$destination" ${lib.escapeShellArg (builtins.toJSON paths)} ${lib.escapeShellArg (builtins.toJSON excludes)}
  python3 ${../scripts/home-state-sqlite.py} --publish "$temporary" "$destination"
''
