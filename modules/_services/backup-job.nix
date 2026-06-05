{
  lib,
  pkgs,
}:
{
  name,
  description,
  backupDir,
  filePattern,
  createBackup,
  owner ? null,
  group ? owner,
  retention ? 7,
  onCalendar ? "daily",
  randomizedDelaySec ? "30min",
  serviceConfig ? { },
}:
let
  pruneBackups = pkgs.writeShellApplication {
    name = "${name}-prune-backups";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      set -euo pipefail
      cd "${backupDir}"
      find . -maxdepth 1 -type f -name '${filePattern}' -printf '%T@ %p\0' \
        | sort -z -rn \
        | tail -z -n +${toString (retention + 1)} \
        | cut -z -d ' ' -f 2- \
        | xargs -0 -r rm -v
    '';
  };

  installBackupDir = lib.optionalAttrs (owner != null) {
    ExecStartPre = "+${lib.getExe' pkgs.coreutils "install"} -d -m 0750 -o ${owner} -g ${group} ${backupDir}";
  };
in
{
  systemd.services."${name}-backup" = {
    description = "Create ${description} backup";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe createBackup;
      ExecStartPost = lib.getExe pruneBackups;
    }
    // installBackupDir
    // serviceConfig;
    wantedBy = [ ];
  };

  systemd.timers."${name}-backup" = {
    description = "Run ${description} backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = onCalendar;
      Persistent = true;
      RandomizedDelaySec = randomizedDelaySec;
    };
  };
}
