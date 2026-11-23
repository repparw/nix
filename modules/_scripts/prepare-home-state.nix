{
  pkgs,
  lib,
}:
{
  home,
  stateRoot,
  persistentStateDir ? null,
  paths,
  excludes ? [ ],
  criticalPaths ? [ ],
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
  # Serialize concurrent exporter runs without blocking on Restic until publish.
  exec 8>"$parent/.prepare.lock"
  flock --exclusive 8
  # Reclaim any orphaned staging directory left behind by a prior SIGKILL/OOM.
  rm -rf "$parent"/.prepare-offsite.*
  temporary=$(mktemp -d "$parent/.prepare-offsite.XXXXXX")
  trap 'rm -rf "$temporary"' EXIT
  # The stage contains only verified SQLite snapshots, a manifest, and
  # Restic root/exclude lists so ordinary files are backed up in place.
  python3 ${../scripts/home-state-sqlite.py} \
    ${lib.escapeShellArg home} \
    "$temporary" \
    "$destination" \
    ${lib.escapeShellArg (builtins.toJSON paths)} \
    ${lib.escapeShellArg (builtins.toJSON excludes)} \
    ${lib.optionalString (persistentStateDir != null) "--persistent-dir ${lib.escapeShellArg persistentStateDir}"} \
    --critical ${lib.escapeShellArg (builtins.toJSON criticalPaths)}
  # Restic holds .stage.lock shared while reading the published SQLite snapshots.
  # Acquire exclusive only for the atomic swap so VACUUM INTO never stalls behind uploads.
  exec 9>"$parent/.stage.lock"
  flock --exclusive 9
  python3 ${../scripts/home-state-sqlite.py} --publish "$temporary" "$destination"
''
