prev: prev.qbittorrent-nox.overrideAttrs (old: {
                    patches = (old.patches or [ ]) ++ [
                      (prev.fetchpatch {
                        url = "https://patch-diff.githubusercontent.com/raw/qbittorrent/qBittorrent/pull/24055.patch";
                        hash = "sha256-XW4ZnyaxBuIb3kny12+T/uTQOFIOVnBRV9qc1AWy6MY=";
                      })
                    ];
                  });
