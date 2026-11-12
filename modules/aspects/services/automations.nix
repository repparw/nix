{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.automations = {
    service-registry = {
      name = "automations";
      definition = {
        auth = "bypass";
        backupRelativePath = "automations";
      };
    };

    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
        serviceName = "automations";
        stateDir = "${cfg.configDir}/${serviceName}";
        watchersFile = "${stateDir}/change-watchers.json";
        mkExtractorWatcher =
          {
            slug,
            label,
            url,
            fetchUrl,
            extractor,
            displayTemplate,
            message,
          }:
          {
            inherit
              slug
              label
              url
              fetchUrl
              extractor
              displayTemplate
              message
              ;
            mode = "extractor";
          };
        defaultWatchers = [
          (
            (mkExtractorWatcher {
              slug = "nixpkgs-security-fleet";
              label = "Accepted Nixpkgs security issues for fleet packages";
              url = "https://tracker.security.nixos.org/issues";
              fetchUrl = "https://tracker.security.nixos.org/api/v1/issues?expand=suggestions";
              extractor = "nixpkgsSecurityIssues";
              displayTemplate = "nixpkgsSecurityIssues";
              message = "New accepted Nixpkgs security issues for fleet packages";
            })
            // {
              fetcher = "curl";
              # Suggestion payloads embed full per-package version and
              # maintainer metadata; single pages now exceed the 2 MiB default.
              maxResponseBytes = 16 * 1024 * 1024;
              packages = [
                "authelia"
                "bazarr"
                "brotli"
                "bun"
                "c-ares"
                "chromium"
                "electron"
                "firefox"
                "git"
                "glibc"
                "home-assistant"
                "jellyfin"
                "linux"
                "miniflux"
                "nix"
                "nodejs_24"
                "nodejs-slim_24"
                "openssh"
                "openssl"
                "paperless-ngx"
                "postgresql"
                "prowlarr"
                "python3"
                "qbittorrent"
                "radarr"
                "redis"
                "sonarr"
                "systemd"
                "traefik"
                "wireguard-tools"
              ];
            }
          )
          (mkExtractorWatcher {
            slug = "8bitdo-ultimate-2c-firmware";
            label = "8BitDo Ultimate 2C firmware";
            url = "https://support.8bitdo.com/#ultimate-2c-wireless";
            fetchUrl = "https://support.8bitdo.com/";
            extractor = "eightBitdoUltimate2cFirmware";
            displayTemplate = "8bitdoFirmware";
            message = "8BitDo Ultimate 2C firmware changed: {{previous}} -> {{current}}\n{{url}}";
          })
          (
            mkExtractorWatcher {
              slug = "nixos-latest-release-notes";
              label = "NixOS latest release notes";
              url = "https://nixos.org/manual/nixos/unstable/release-notes";
              fetchUrl = "https://nixos.org/manual/nixos/unstable/release-notes";
              extractor = "nixosReleaseChanges";
              displayTemplate = "nixosReleaseChanges";
              message = "**NixOS {{version}} release notes updated**\n{{url}}\n\n**New modules:**\n{{newModules}}\n\n**Breaking changes:**\n{{breakingChanges}}\n\n**Other notable changes:**\n{{otherChanges}}";
            }
            // {
              # Unstable release notes are a single accumulating page, 1.6 MiB
              # as of 2026-11-05 and growing toward the 2 MiB default.
              maxResponseBytes = 16 * 1024 * 1024;
            }
          )
        ];
        defaultWatchersFile = pkgs.writeText "change-detection-default-watchers.json" (
          builtins.toJSON defaultWatchers
        );
        changeDetectionScript = pkgs.writeText "change-detection.mjs" (
          builtins.readFile ./automations/change-detection.mjs
        );
        changeDetection = pkgs.writeShellApplication {
          name = "change-detection";
          runtimeInputs = [
            pkgs.nodejs_24
            pkgs.curl
          ];
          text = ''
            node ${changeDetectionScript} ${watchersFile} ${stateDir}/change-detection-state.json ${defaultWatchersFile}
          '';
        };
      in
      {
        systemd.tmpfiles.rules = [
          "d ${stateDir} 0750 root root - -"
        ];

        systemd.services.change-detection = {
          description = "Check watched pages and notify Discord when values change";
          preStart = ''
            if [ ! -s ${watchersFile} ]; then
              echo "missing watcher config: ${watchersFile}" >&2
              exit 1
            fi
          '';
          serviceConfig.Type = "oneshot";
          path = [ pkgs.nodejs_24 ];
          # Posts through the fleet bot identity (token + channel), like every
          # other watcher, instead of a per-aspect webhook.
          script = ''
            # shellcheck disable=SC1091
            source /run/secrets/hermes-env
            export DISCORD_BOT_TOKEN DISCORD_CHANNEL_ID=${config.modules.services.discordChannelId}
            ${lib.getExe changeDetection}
          '';
        };

        systemd.timers.change-detection = {
          description = "Run change detection every six hours";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 00/6:13:00";
            Persistent = true;
            RandomizedDelaySec = "5min";
          };
        };
      };
  };
}
