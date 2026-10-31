{ den, lib, ... }:
{
  # This overlay belongs to the qBittorrent container, not the host.
  den.aspects.nixos-services.provides.arr.nixos.containers.qbittorrent.config.nixpkgs.overlays = [
    (_final: prev: {
      qbittorrent-nox = prev.qbittorrent-nox.overrideAttrs (old: {
        # qBittorrent 5.3 introduced an extra constructor initializer
        # after the upstream PR's insertion point. Temporarily remove it.
        prePatch =
          (old.prePatch or "")
          + lib.optionalString (lib.versionAtLeast old.version "5.3.0") ''
            substituteInPlace src/base/bittorrent/sessionimpl.cpp \
              --replace-fail \
              $'    , m_backupTorrentFilesRegistry {new KeyValueDataStorage(u"BackupTorrentFiles"_s, this)}\n{' \
              '{'
          '';
        patches = (old.patches or [ ]) ++ [
          (prev.fetchpatch {
            url = "https://patch-diff.githubusercontent.com/raw/qbittorrent/qBittorrent/pull/24055.patch";
            hash = "sha256-XW4ZnyaxBuIb3kny12+T/uTQOFIOVnBRV9qc1AWy6MY=";
          })
        ];
        # Restore the 5.3 initializer after the PR's min-space initializer.
        # Both substitutions fail closed if future upstream source moves.
        postPatch =
          (old.postPatch or "")
          + lib.optionalString (lib.versionAtLeast old.version "5.3.0") ''
            substituteInPlace src/base/bittorrent/sessionimpl.cpp \
              --replace-fail \
              $'    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}\n{' \
              $'    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}\n    , m_backupTorrentFilesRegistry {new KeyValueDataStorage(u"BackupTorrentFiles"_s, this)}\n{'
          '';
      });
    })
  ];
}
