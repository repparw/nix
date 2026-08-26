{
  lib,
  config,
  ...
}:
# Service inventory: THE single source of truth for service definitions
# (routing-level facts plus operational metadata like backup paths).
#
# Owning modules (_services/*.nix, aspects/services/*.nix) must NOT redefine
# `modules.services.definitions.<name>`: definitions set elsewhere shadow an
# inventory entry wholesale (priorities conflict at entry granularity, no
# leaf merging happens), which silently reverts any field only set here.
#
# `host` marks which machine runs the backend:
#   - null            -> local to whichever host includes this file
#   - "alpha"/"pi"    -> reached via modules.services.hostAddresses and
#                        publishedPort (when the container port had to be
#                        remapped for publishing)
let
  cfg = config.modules.services;
in
{
  config = {
    modules.services.hostAddresses = {
      alpha = "192.168.0.18";
      pi = "192.168.0.4";
    };

    modules.services.definitions = lib.mapAttrs (_: lib.mkDefault) {
      # --- alpha nspawn containers (published via forwardPorts) ---
      jellyfin = {
        hostname = "jellyfin";
        containerAddress = "10.231.136.10";
        port = 8096;
        auth = "bypass";
        host = "alpha";
        monitor = true;
        backup.path = "${cfg.configDir}/jellyfin/data/backups";
      };
      bazarr = {
        hostname = "bazarr";
        containerAddress = "10.231.136.2";
        port = 6767;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
        backup.path = "${cfg.configDir}/bazarr/backup";
      };
      prowlarr = {
        hostname = "prowlarr";
        containerAddress = "10.231.136.3";
        port = 9696;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
        backup.path = "${cfg.configDir}/prowlarr/Backups";
      };
      qbittorrent = {
        hostname = "qbit";
        containerAddress = "10.231.136.4";
        port = 8080;
        publishedPort = 18080; # remapped: glance historically owned 18085, qbit keeps 18080
        auth = "external";
        host = "alpha";
        monitor = true;
        backup.path = "${cfg.configDir}/qbittorrent";
      };
      radarr = {
        hostname = "radarr";
        containerAddress = "10.231.136.5";
        port = 7878;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
        backup.path = "${cfg.configDir}/radarr/Backups";
      };
      sonarr = {
        hostname = "sonarr";
        containerAddress = "10.231.136.6";
        port = 8989;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
        backup.path = "${cfg.configDir}/sonarr/Backups";
      };
      paperless = {
        hostname = "paper";
        containerAddress = "10.231.136.12";
        port = 8000;
        auth = "one_factor";
        host = "alpha";
        monitor = true;
        backup.path = "${cfg.configDir}/paperless/export";
      };
      finance = {
        hostname = "finance";
        port = 3000;
        auth = "one_factor";
        host = "alpha";
      };

      # --- pi ---
      # Edge ingress stack (traefik/authelia/ddclient/glance).
      authelia = {
        hostname = "auth";
        containerAddress = "10.231.136.7";
        port = 9091;
        auth = "bypass";
        monitor = true;
        backup.path = "${cfg.configDir}/authelia";
      };
      glance = {
        containerAddress = "10.231.136.15";
        port = 8080;
        auth = "bypass";
      };
      # Host-native miniflux + its PostgreSQL (issue #44). Reachable from
      # both the host traefik and sibling containers (glance probes) via
      # pi's nspawn bridge gateway; the module binds 0.0.0.0.
      miniflux = {
        hostname = "rss";
        containerAddress = "10.231.136.1";
        port = 8081;
        auth = "one_factor";
        monitor = true;
        backup.path = "${cfg.configDir}/miniflux";
      };
      # Always-on Steam card farming (issue #43).
      archisteamfarm = {
        containerAddress = "10.231.136.13";
        auth = "bypass";
        backup.path = "${cfg.configDir}/archisteamfarm";
      };
      # Page-change watcher oneshot (issue #45); no inbound routing.
      automations = {
        auth = "bypass";
        backup.path = "${cfg.configDir}/automations";
      };

      # --- unowned locals ---
      hass = {
        hostname = "home";
        containerAddress = "10.231.136.2"; # pi's own nspawn bridge
        port = 8123;
        auth = "bypass";
      };
    };
  };
}
