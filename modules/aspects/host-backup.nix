{ den, ... }:
{
  den.aspects.host-backup = {
    includes = [ den.aspects.backup ];
    nixos =
      { config, lib, ... }:
      {
        modules.backup = {
          paths = [
            "/etc"
            "/boot"
            "/root"
            "/home/repparw"
            "/var/lib/nixos"
            "/var/lib/nixos-containers"
            "/var/lib/systemd/timers"
            "/var/lib/host-recovery"
          ]
          # Restic stops at a different device, including nested boot partitions.
          ++ lib.filter (path: lib.hasPrefix "/boot/" path) (
            lib.attrNames (
              lib.filterAttrs (
                _: fs:
                lib.elem fs.fsType [
                  "ext4"
                  "vfat"
                  "btrfs"
                  "xfs"
                ]
              ) config.fileSystems
            )
          )
          ++ lib.optional config.services.traefik.enable "/var/lib/traefik";
          excludes = [
            "**/.cache/**"
            "**/node_modules/**"
            "**/.direnv/**"
            "**/__pycache__/**"
            "/home/repparw/.swapfile"
            "/home/repparw/.local/share/Trash/**"
          ]
          ++ map (path: "/var/lib/nixos-containers/*/${path}") [
            "nix"
            "proc"
            "sys"
            "dev"
            "run"
            "tmp"
          ];
        };
        services.restic.backups.offsite.extraBackupArgs = [ "--one-file-system" ];
        # Keep existing checkpoints readable and backed up after retiring the tool.
        systemd.tmpfiles.rules = [ "d /var/lib/host-recovery 0700 root root -" ];
      };
  };
}
