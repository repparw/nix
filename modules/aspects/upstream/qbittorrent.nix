{ den, lib, ... }:
{
  # This overlay belongs to the qBittorrent container, not the host.
  den.aspects.nixos-services.provides.arr.nixos.containers.qbittorrent.config.nixpkgs.overlays = [
    (_final: prev: {
      qbittorrent-nox = prev.qbittorrent-nox.overrideAttrs (old: {
        # The unrebased min-space PR expects this to be the last
        # constructor initializer. qBittorrent 5.3 introduced another one.
        # Temporarily remove it only while applying the PR patch.
        prePatch =
          (old.prePatch or "")
          + lib.optionalString (lib.versionAtLeast old.version "5.3.0") ''
            substituteInPlace src/base/bittorrent/sessionimpl.cpp \
              --replace-fail \
              
        patches = (old.patches or [ ]) ++ [
          (prev.fetchpatch {
            url = "https://patch-diff.githubusercontent.com/raw/qbittorrent/qBittorrent/pull/24055.patch";
            hash = "sha256-XW4ZnyaxBuIb3kny12+T/uTQOFIOVnBRV9qc1AWy6MY=";
          })
        ];
        # Restore the 5.3 initializer after the min-space initializer.
        # Fail closed on any future upstream source-layout change.
        postPatch =
          (old.postPatch or "")
          + lib.optionalString (lib.versionAtLeast old.version "5.3.0") ''
            substituteInPlace src/base/bittorrent/sessionimpl.cpp \
              --replace-fail \
              
      });
    })
  ];
}
    , m_backupTorrentFilesRegistry {new KeyValueDataStorage(u"BackupTorrentFiles"_s, this)}\n{' \
              '{'
          '';
        patches = (old.patches or [ ]) ++ [
          (prev.fetchpatch {
            url = "https://patch-diff.githubusercontent.com/raw/qbittorrent/qBittorrent/pull/24055.patch";
            hash = "sha256-XW4ZnyaxBuIb3kny12+T/uTQOFIOVnBRV9qc1AWy6MY=";
          })
        ];
        # Restore the 5.3 initializer after the min-space initializer.
        # Fail closed on any future upstream source-layout change.
        postPatch = (old.postPatch or "") + lib.optionalString (lib.versionAtLeast old.version "5.3.0") ''
          substituteInPlace src/base/bittorrent/sessionimpl.cpp \
            --replace-fail \
            '    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}
{' '    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}
    , m_backupTorrentFilesRegistry {new KeyValueDataStorage(u"BackupTorrentFiles"_s, this)}
{'
        '';
      });
    })
  ];
}
    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}\n{' \
              
      });
    })
  ];
}
    , m_backupTorrentFilesRegistry {new KeyValueDataStorage(u"BackupTorrentFiles"_s, this)}\n{' \
              '{'
          '';
        patches = (old.patches or [ ]) ++ [
          (prev.fetchpatch {
            url = "https://patch-diff.githubusercontent.com/raw/qbittorrent/qBittorrent/pull/24055.patch";
            hash = "sha256-XW4ZnyaxBuIb3kny12+T/uTQOFIOVnBRV9qc1AWy6MY=";
          })
        ];
        # Restore the 5.3 initializer after the min-space initializer.
        # Fail closed on any future upstream source-layout change.
        postPatch = (old.postPatch or "") + lib.optionalString (lib.versionAtLeast old.version "5.3.0") ''
          substituteInPlace src/base/bittorrent/sessionimpl.cpp \
            --replace-fail \
            '    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}
{' '    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}
    , m_backupTorrentFilesRegistry {new KeyValueDataStorage(u"BackupTorrentFiles"_s, this)}
{'
        '';
      });
    })
  ];
}
    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}\n    , m_backupTorrentFilesRegistry {new KeyValueDataStorage(u"BackupTorrentFiles"_s, this)}\n{'
          '';
      });
    })
  ];
}
    , m_backupTorrentFilesRegistry {new KeyValueDataStorage(u"BackupTorrentFiles"_s, this)}\n{' \
              '{'
          '';
        patches = (old.patches or [ ]) ++ [
          (prev.fetchpatch {
            url = "https://patch-diff.githubusercontent.com/raw/qbittorrent/qBittorrent/pull/24055.patch";
            hash = "sha256-XW4ZnyaxBuIb3kny12+T/uTQOFIOVnBRV9qc1AWy6MY=";
          })
        ];
        # Restore the 5.3 initializer after the min-space initializer.
        # Fail closed on any future upstream source-layout change.
        postPatch = (old.postPatch or "") + lib.optionalString (lib.versionAtLeast old.version "5.3.0") ''
          substituteInPlace src/base/bittorrent/sessionimpl.cpp \
            --replace-fail \
            '    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}
{' '    , m_minFreeDiskSpace {BITTORRENT_SESSION_KEY(u"MinFreeDiskSpace"_s), 0LL}
    , m_backupTorrentFilesRegistry {new KeyValueDataStorage(u"BackupTorrentFiles"_s, this)}
{'
        '';
      });
    })
  ];
}
