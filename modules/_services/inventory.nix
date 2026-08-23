{
  lib,
  ...
}:
# Cross-host service inventory: routing-level facts for every public backend,
# written so any host's Traefik can route the full estate. Values are
# `mkDefault` so the owning service modules (which carry operational settings
# like backup paths and container addresses) always take precedence where they
# are included.
#
# `host` marks which machine runs the backend:
#   - null            -> local to whichever host includes this file
#   - "alpha"/"pi"    -> reached via modules.services.hostAddresses and
#                        publishedPort (when the container port had to be
#                        remapped for publishing)
{
  config = {
    modules.services.definitions = lib.mapAttrs (_: lib.mkDefault) {
      # --- alpha containers (published via nspawn forwardPorts) ---
      jellyfin = {
        hostname = "jellyfin";
        port = 8096;
        auth = "bypass";
        host = "alpha";
        monitor = true;
      };
      bazarr = {
        hostname = "bazarr";
        port = 6767;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
      };
      prowlarr = {
        hostname = "prowlarr";
        port = 9696;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
      };
      qbittorrent = {
        hostname = "qbit";
        port = 8080;
        publishedPort = 18080; # shares 8080 with glance on alpha's LAN iface
        auth = "external";
        host = "alpha";
        monitor = true;
      };
      radarr = {
        hostname = "radarr";
        port = 7878;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
      };
      sonarr = {
        hostname = "sonarr";
        port = 8989;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
      };
      paperless = {
        hostname = "paper";
        port = 8000;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
      };
      glance = {
        port = 8080;
        publishedPort = 18085; # apex-domain dashboard; no hostname by design
        auth = "bypass";
        host = "alpha";
      };

      # --- alpha host-native listeners ---
      miniflux = {
        hostname = "rss";
        port = 8081; # binds 0.0.0.0 in miniflux.nix
        auth = "one_factor";
        host = "alpha";
        monitor = true;
      };
      finance = {
        hostname = "finance";
        port = 3000;
        auth = "one_factor";
        host = "alpha";
      };

      # --- pi-local ---
      hass = {
        hostname = "home";
        containerAddress = "10.231.136.2"; # pi's own nspawn bridge
        port = 8123;
        auth = "bypass";
      };
    };
  };
}
