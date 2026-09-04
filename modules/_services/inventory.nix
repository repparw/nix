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
      epsilon = "10.5.5.3";
    };

    modules.services.definitions = lib.mapAttrs (_: lib.mkDefault) {
      # --- alpha ---
      jellyfin = {
        hostname = "jellyfin";
        port = 8096;
        auth = "bypass";
        host = "alpha";
        container = true;
        monitor = true;
        healthcheck = "/health";
        backup.path = "${cfg.configDir}/jellyfin/data/backups";
      };
      bazarr = {
        hostname = "bazarr";
        port = 6767;
        auth = "one_factor";
        host = "alpha";
        container = true;
        monitor = true;
        healthcheck = "/health";
        backup.path = "${cfg.configDir}/bazarr/backup";
      };
      prowlarr = {
        hostname = "prowlarr";
        port = 9696;
        auth = "one_factor";
        host = "alpha";
        container = true;
        monitor = true;
        healthcheck = "/ping";
        backup.path = "${cfg.configDir}/prowlarr/Backups";
      };
      qbittorrent = {
        hostname = "qbit";
        port = 8080;
        publishedPort = 18080;
        auth = "external";
        host = "alpha";
        container = true;
        monitor = true;
        backup.path = "${cfg.configDir}/qbittorrent";
      };
      radarr = {
        hostname = "radarr";
        port = 7878;
        auth = "one_factor";
        host = "alpha";
        container = true;
        monitor = true;
        healthcheck = "/ping";
        backup.path = "${cfg.configDir}/radarr/Backups";
      };
      sonarr = {
        hostname = "sonarr";
        port = 8989;
        auth = "one_factor";
        host = "alpha";
        container = true;
        monitor = true;
        healthcheck = "/ping";
        backup.path = "${cfg.configDir}/sonarr/Backups";
      };
      paperless = {
        hostname = "paper";
        port = 8000;
        auth = "one_factor";
        host = "alpha";
        container = true;
        monitor = true;
        backup.path = "${cfg.configDir}/paperless/export";
      };
      finance = {
        hostname = "finance";
        port = 3000;
        auth = "one_factor";
        host = "alpha";
      };

      # --- epsilon ---
      authelia = {
        hostname = "auth";
        port = 9091;
        auth = "bypass";
        host = "epsilon";
        container = true;
        monitor = true;
        backup.path = "${cfg.configDir}/authelia";
      };
      glance = {
        port = 8080;
        auth = "bypass";
        host = "epsilon";
        container = true;
      };
      miniflux = {
        hostname = "rss";
        port = 8081;
        auth = "one_factor";
        host = "epsilon";
        container = true;
        monitor = true;
        healthcheck = "/healthcheck";
        backup.path = "${cfg.configDir}/miniflux";
      };
      hermes = {
        host = "epsilon";
        container = true;
      };
      archisteamfarm = {
        auth = "bypass";
        host = "pi";
        container = true;
        backup.path = "${cfg.configDir}/archisteamfarm";
      };
      automations = {
        auth = "bypass";
        host = "pi";
        backup.path = "${cfg.configDir}/automations";
      };
      # --- pi ---
      # homeassistant runs on pi but serves through epsilon's edge: routing it at its
      # bridge address needs the router to forward 10.231.136.0/24 (broken,
      # and ambiguous with alpha's bridge which also uses that /24). Reach it
      # like the other remote backends via pi's published 8123 (nspawn
      # forwardPorts DNATs to the container).
      homeassistant = {
        hostname = "home";
        host = "pi";
        container = true;
        port = 8123;
        auth = "bypass";
        monitor = true;
      };
    };
  };
}
