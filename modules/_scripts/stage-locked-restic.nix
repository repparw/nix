{
  pkgs,
  lib,
}:
{
  lockFile,
  restic ? pkgs.restic,
}:
# A shared lock must cover the actual Restic traversal, not just preStart.
# -o/--option flags can precede the backup subcommand, so examine all args.
pkgs.writeShellScriptBin "restic" ''
  for arg in "$@"; do
    if [ "$arg" = backup ]; then
      exec ${pkgs.util-linux}/bin/flock --shared ${lib.escapeShellArg lockFile} ${lib.getExe restic} "$@"
    fi
  done
  exec ${lib.getExe restic} "$@"
''
