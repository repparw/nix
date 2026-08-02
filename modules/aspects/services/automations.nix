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
        mkRegexWatcher =
          {
            slug,
            label,
            url,
            pattern,
            message,
            fetcher ? null,
          }:
          {
            inherit
              slug
              label
              url
              pattern
              message
              ;
            mode = "regex";
            flags = "is";
          }
          // lib.optionalAttrs (fetcher != null) { inherit fetcher; };
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
          (mkRegexWatcher {
            slug = "nzb360-liteapks";
            label = "nzb360 LiteAPKs version";
            url = "https://liteapks.com/download/nzb360-73320/1";
            fetcher = "curl";
            pattern = ''<button[^>]*class="[^"]*dl-version-tab[^"]*"[^>]*>[\s\S]*?<span[^>]*>v([0-9.]+)'';
            message = "nzb360 LiteAPKs version changed: {{previous}} -> {{current}}\n{{url}}";
          })
          (mkExtractorWatcher {
            slug = "8bitdo-ultimate-2c-firmware";
            label = "8BitDo Ultimate 2C firmware";
            url = "https://support.8bitdo.com/#ultimate-2c-wireless";
            fetchUrl = "https://support.8bitdo.com/";
            extractor = "eightBitdoUltimate2cFirmware";
            displayTemplate = "8bitdoFirmware";
            message = "8BitDo Ultimate 2C firmware changed: {{previous}} -> {{current}}\n{{url}}";
          })
          (mkRegexWatcher {
            slug = "argentina-open-finance-objectives";
            label = "Argentina open finance: BCRA implementation plan";
            url = "https://www.bcra.gob.ar/objetivos-y-planes/";
            pattern = ''(Sistema\s+de\s+Finanzas\s+Abiertas[\s\S]{0,1800})'';
            message = "Argentina open-finance implementation plan changed.\n{{url}}";
          })
          (mkRegexWatcher {
            slug = "argentina-open-finance-api-catalog";
            label = "Argentina open finance: BCRA API catalog";
            url = "https://www.bcra.gob.ar/apis-banco-central/";
            pattern = ''(Actualmente,?\s+este\s+sitio\s+ofrece\s+las\s+siguientes\s+API:[\s\S]{0,2200}Régimen\s+de\s+Transparencia)'';
            message = "BCRA API catalog changed; check for an open-finance integration surface.\n{{url}}";
          })
          (mkRegexWatcher {
            slug = "argentina-open-finance-public-consultations";
            label = "Argentina open finance: BCRA public consultations";
            url = "https://www.bcra.gob.ar/listado-servicios/";
            pattern = ''(Consulta\s+pública\s+sobre\s+proyectos\s+normativos[\s\S]{0,800})'';
            message = "BCRA public-consultation index changed.\n{{url}}";
          })
          (mkRegexWatcher {
            slug = "argentina-open-finance-communications-index";
            label = "Argentina open finance: BCRA communications index";
            url = "https://www.bcra.gob.ar/en/communications-search-engine/";
            pattern = ''(Annual\s+report\s+of\s+communications:[\s\S]{0,1600})'';
            message = "BCRA communications index changed; review new regulatory material.\n{{url}}";
          })
        ];
        defaultWatchersFile = pkgs.writeText "change-detection-default-watchers.json" (
          builtins.toJSON defaultWatchers
        );
        discordWebhookFile = config.sops.secrets.discordWebhook.path;
        changeDetectionScript = pkgs.writeText "change-detection.mjs" (
          builtins.readFile ./automations/change-detection.mjs
        );
        changeDetection = pkgs.writeShellApplication {
          name = "change-detection";
          runtimeInputs = [
            pkgs.nodejs
            pkgs.curl
          ];
          text = ''
            node ${changeDetectionScript} ${watchersFile} ${stateDir}/change-detection-state.json "$CREDENTIALS_DIRECTORY/discordWebhook" ${defaultWatchersFile}
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
