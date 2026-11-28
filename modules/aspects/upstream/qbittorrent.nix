{ den, ... }:
{
  # This overlay belongs to the qBittorrent container, not the host.
  den.aspects.nixos-services.provides.arr.nixos.containers.qbittorrent.config.nixpkgs.overlays = [
    (_final: prev: {
      qbittorrent-nox = prev.qbittorrent-nox.overrideAttrs (old: {
        # Add the configurable minimum free disk space threshold.
        patches = (old.patches or [ ]) ++ [
          (prev.fetchpatch {
            url = "https://patch-diff.githubusercontent.com/raw/qbittorrent/qBittorrent/pull/24828.patch";
            hash = "sha256-CIy5uehjSiJvZhFJHj93SPvKxy5Bowa5Sv2YcYew9fM=";
          })
        ];
      });
    })
  ];
}
