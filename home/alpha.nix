{...}: let
in {
  services.spotifyd.enable = true;

  modules.jellyfin-mpv-shim.enable = true;
}
