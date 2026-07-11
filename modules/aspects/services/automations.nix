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
        initialStateFile = pkgs.writeText "change-detection-initial-state.json" (
          builtins.toJSON {
            watchers = {
              nzb360-liteapks = {
                current = "23.5";
                currentKey = "23.5";
                displayValue = "23.5";
                checkedAt = "2026-07-10T15:13:22.544Z";
                url = "https://liteapks.com/nzb360.html";
              };
              "8bitdo-ultimate-2c-firmware" = {
                current = {
                  controller = "1.09";
                  adapter = "1.03";
                };
                currentKey = "{\"adapter\":\"1.03\",\"controller\":\"1.09\"}";
                displayValue = "controller v1.09, adapter v1.03";
                checkedAt = "2026-07-10T15:13:23.511Z";
                url = "https://support.8bitdo.com/#ultimate-2c-wireless";
              };
            };
          }
        );
        changeDetectionScript = pkgs.writeText "change-detection.mjs" ''
          import fs from "node:fs";
          import path from "node:path";

          const [, , watchersPath, statePath, initialStatePath, discordWebhookPath] = process.argv;

          if (!watchersPath || !statePath || !initialStatePath || !discordWebhookPath) {
            throw new Error("usage: change-detection <watchers.json> <state.json> <initial-state.json> <discord-webhook-file>");
          }

          const watchers = JSON.parse(fs.readFileSync(watchersPath, "utf8"));
          if (!Array.isArray(watchers)) {
            throw new Error("watchers config must contain an array");
          }

          function readState(file, fallbackFile) {
            try {
              return JSON.parse(fs.readFileSync(file, "utf8"));
            } catch (error) {
              if (error.code === "ENOENT") return JSON.parse(fs.readFileSync(fallbackFile, "utf8"));
              throw error;
            }
          }

          function writeState(file, state) {
            fs.mkdirSync(path.dirname(file), { recursive: true });
            const tmp = `''${file}.tmp`;
            fs.writeFileSync(tmp, `''${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
            fs.renameSync(tmp, file);
          }

          function stableStringify(value) {
            if (value === null || typeof value !== "object") return JSON.stringify(value);
            if (Array.isArray(value)) return `[''${value.map(stableStringify).join(",")}]`;
            return `{''${Object.keys(value).sort().map((key) => `''${JSON.stringify(key)}:''${stableStringify(value[key])}`).join(",")}}`;
          }

          function extractEightBitdoUltimate2cFirmware(body) {
            const anchor = 'id="ultimate-2c-wireless"';
            const start = body.indexOf(anchor);
            if (start === -1) throw new Error("Could not find Ultimate 2C Wireless update log section");

            const section = body.slice(start, start + 5000);
            const controllerMatch = /<!--\s*Controller firmware\s*-->[\s\S]*?<h5>\s*Firmware\s+v([^<\s]+)\s*<\/h5>/i.exec(section);
            const adapterMatch = /<!--\s*Adapter firmware\s*-->[\s\S]*?<h5>\s*Firmware\s+v([^<\s]+)\s*<\/h5>/i.exec(section);

            if (!controllerMatch) throw new Error("Could not extract Ultimate 2C controller firmware version");
            if (!adapterMatch) throw new Error("Could not extract Ultimate 2C adapter firmware version");

            return {
              controller: controllerMatch[1].trim(),
              adapter: adapterMatch[1].trim(),
            };
          }

          function displayValue(watcher, current, currentKey) {
            if (watcher.displayTemplate === "8bitdoFirmware") {
              return `controller v''${current.controller}, adapter v''${current.adapter}`;
            }
            return typeof current === "string" ? current : currentKey;
          }

          async function fetchText(watcher) {
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), watcher.timeoutMs ?? 30000);
            try {
              const response = await fetch(watcher.fetchUrl ?? watcher.url, {
                method: watcher.method ?? "GET",
                headers: {
                  "User-Agent": "change-monitor/1.0",
                  "Accept": "text/html,application/xhtml+xml,application/json,text/plain",
                  ...(watcher.headers ?? {}),
                },
                signal: controller.signal,
              });
              if (!response.ok) {
                throw new Error(`''${watcher.slug} returned HTTP ''${response.status}`);
              }
              return await response.text();
            } finally {
              clearTimeout(timeout);
            }
          }

          function extractValue(watcher, body) {
            if (watcher.mode === "regex") {
              for (const pattern of (watcher.patterns ?? [watcher.pattern]).filter(Boolean)) {
                const match = new RegExp(pattern, watcher.flags ?? "i").exec(body);
                if (match) return String(match[watcher.group ?? 1]).trim();
              }
              throw new Error(`Could not extract value for ''${watcher.slug}`);
            }

            if (watcher.mode === "extractor" && watcher.extractor === "eightBitdoUltimate2cFirmware") {
              return extractEightBitdoUltimate2cFirmware(body);
            }

            throw new Error(`Unknown watcher mode for ''${watcher.slug}`);
          }

          async function notifyDiscord(webhookPath, content) {
            const webhookUrl = fs.readFileSync(webhookPath, "utf8").trim();
            const response = await fetch(webhookUrl, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ username: "automations", content }),
            });
            if (!response.ok) {
              throw new Error(`Discord webhook returned HTTP ''${response.status}`);
            }
          }

          const state = readState(statePath, initialStatePath);
          state.watchers ??= {};

          for (const watcher of watchers.filter((entry) => entry.enabled !== false)) {
            const body = await fetchText(watcher);
            const current = extractValue(watcher, body);
            const currentKey = typeof current === "string" ? current : stableStringify(current);
            const currentDisplay = displayValue(watcher, current, currentKey);
            const previous = state.watchers[watcher.slug] ?? null;
            const previousKey = previous?.currentKey;
            const previousDisplay = previous?.displayValue ?? previous?.current ?? null;
            const changed = Boolean(previousKey && previousKey !== currentKey);

            state.watchers[watcher.slug] = {
              current,
              currentKey,
              displayValue: currentDisplay,
              checkedAt: new Date().toISOString(),
              url: watcher.url,
            };

            if (changed) {
              const template = watcher.message ?? `''${watcher.label ?? watcher.slug} changed: {{previous}} -> {{current}}\n{{url}}`;
              const content = template
                .replaceAll("{{previous}}", previousDisplay ?? previousKey)
                .replaceAll("{{current}}", currentDisplay)
                .replaceAll("{{url}}", watcher.url);
              await notifyDiscord(discordWebhookPath, content);
              console.log(`''${watcher.slug}: changed from ''${previousDisplay ?? previousKey} to ''${currentDisplay}`);
            } else {
              console.log(`''${watcher.slug}: unchanged at ''${currentDisplay}`);
            }
          }

          writeState(statePath, state);
        '';
        changeDetection = pkgs.writeShellApplication {
          name = "change-detection";
          runtimeInputs = [ pkgs.nodejs ];
          text = ''
            node ${changeDetectionScript} ${watchersFile} ${stateDir}/change-detection-state.json ${initialStateFile} "$CREDENTIALS_DIRECTORY/discordWebhook"
          '';
        };
      in
      {
        systemd.tmpfiles.rules = [
          "d ${stateDir} 0750 root root - -"
        ];

        modules.services.inventory.${serviceName} = {
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
