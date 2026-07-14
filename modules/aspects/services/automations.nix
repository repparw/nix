{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.automations = {
    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
        serviceName = "automations";
        stateDir = "${cfg.configDir}/${serviceName}";
        watchersFile = "${stateDir}/change-watchers.json";
        discordWebhookFile = config.sops.secrets.discordWebhook.path;
        changeDetectionScript = pkgs.writeText "change-detection.mjs" (
          builtins.readFile ./automations/change-detection.mjs
        );
        changeDetection = pkgs.writeShellApplication {
          name = "change-detection";
          runtimeInputs = [ pkgs.nodejs ];
          text = ''
            node ${changeDetectionScript} ${watchersFile} ${stateDir}/change-detection-state.json "$CREDENTIALS_DIRECTORY/discordWebhook"
          '';
        };
      in
      {
        sops.secrets.discordWebhook = {
          sopsFile = ../../../secrets/automations.sops.yaml;
          owner = "root";
          mode = "0400";
        };

        systemd.tmpfiles.rules = [
          "d ${stateDir} 0750 root root - -"
        ];

        modules.services.definitions.${serviceName} = {
          auth = "bypass";
          backup.path = stateDir;
        };

        systemd.services.change-detection = {
          description = "Check watched pages and notify Discord when values change";
          preStart = ''
            if [ ! -s ${watchersFile} ]; then
              echo "missing watcher config: ${watchersFile}" >&2
              exit 1
            fi
          '';
          serviceConfig = {
            Type = "oneshot";
            LoadCredential = "discordWebhook:${discordWebhookFile}";
          };
          path = [ pkgs.nodejs ];
          script = lib.getExe changeDetection;
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
