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
        defaultWatchers = import ../../_services/automations-watchers.nix;
        defaultWatchersFile = pkgs.writeText "change-detection-default-watchers.json" (
          builtins.toJSON defaultWatchers
        );
        changeDetectionScript = pkgs.writeText "change-detection.mjs" (
          builtins.readFile ./automations/change-detection.mjs
        );
        changeDetection = pkgs.writeShellApplication {
          name = "change-detection";
          runtimeInputs = [
            pkgs.nodejs-runtime
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
          path = [ pkgs.nodejs-runtime ];
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
