{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.epic-freegames-portal = {
    service-registry = {
      name = "epic-freegames-portal";
      definition = {
        auth = "bypass";
        backupRelativePath = "epic-freegames-portal";
      };
    };

    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
        stateDir = "${cfg.configDir}/epic-freegames-portal";
        portal = pkgs.callPackage ../../_packages/epicgames-freegames-node.nix { };
        configFile = pkgs.writeText "epic-freegames-portal-config.json" (
          builtins.toJSON {
            # Detection runs four times a day like upstream's default; each
            # run is cheap API calls plus one headed browser for cookies.
            # An unset email leaves the daemon idle until configured.
            accounts = lib.optionals (config.modules.services.epic-freegames-portal.email != "") [
              { email = config.modules.services.epic-freegames-portal.email; }
            ];
            notifiers = [
              {
                type = "webhook";
                url = "http://127.0.0.1:3999";
              }
            ];
            # The device-auth redirect portal. For the trial it is reachable
            # through an SSH tunnel: ssh -N -L 3000:127.0.0.1:3000 pi
            webPortalConfig.baseUrl = "http://localhost:3000";
          }
        );
      in
      {
        options.modules.services.epic-freegames-portal.email = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Epic account email; also the label keying device-auth sessions.";
        };

        config = {
          users.users.epicfgc = {
            isSystemUser = true;
            group = "epicfgc";
            home = stateDir;
          };
          users.groups.epicfgc = { };

          systemd.tmpfiles.rules = [
            "d ${stateDir} 0700 epicfgc epicfgc - -"
            "L+ ${stateDir}/config.json - - - - ${configFile}"
          ];

          # claabs' generic webhook notifications {account, reason, url} go to
          # this relay, which posts them to the fleet channel with the Discord
          # bot token. The bot cannot manage channel webhooks, which claabs'
          # native Discord notifier requires.
          systemd.services.epic-freegames-relay = {
            description = "Discord relay for the Epic free-games portal";
            wantedBy = [ "multi-user.target" ];
            environment.DISCORD_CHANNEL_ID = cfg.discordChannelId;
            serviceConfig = {
              Type = "simple";
              EnvironmentFile = "/run/secrets/hermes-env";
              ExecStart = "${pkgs.python3}/bin/python3 ${./epic-freegames-portal/discord-relay.py}";
              Restart = "always";
              RestartSec = "30s";
              DynamicUser = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              ProtectSystem = "strict";
            };
          };

          # The portal daemon schedules its own detection runs (upstream cron
          # in-process) and drives a headed patchright Chromium for cookie and
          # device-auth flows, so it needs a virtual display. The first login
          # posts a device-auth link; approving it in any browser stores a
          # long-lived refresh token, after which no storefront browsing is
          # needed at all.
          systemd.services.epic-freegames-portal = {
            description = "Epic free-games device-auth portal (claabs)";
            wants = [ "network-online.target" ];
            after = [
              "network-online.target"
              "epic-freegames-relay.service"
            ];
            environment = {
              HOME = stateDir;
              CONFIG_DIR = stateDir;
              BROWSER_PATH = "${pkgs.chromium}/bin/chromium";
            };
            preStart = ''
              mkdir -p "$CONFIG_DIR/users"
            '';
            serviceConfig = {
              Type = "simple";
              User = "epicfgc";
              Group = "epicfgc";
              Restart = "on-failure";
              RestartSec = "5min";
              ExecStart = pkgs.writeShellApplication {
                name = "epic-freegames-portal-start";
                runtimeInputs = with pkgs; [
                  coreutils
                  nodejs_26
                  xorg-server
                ];
                text = ''
                  export DISPLAY=:98
                  Xvfb :98 -screen 0 1920x1080x24 -nolisten tcp &
                  xvfb_pid=$!
                  for _ in $(seq 1 50); do
                    [ -S /tmp/.X11-unix/X98 ] && break
                    kill -0 "$xvfb_pid" 2>/dev/null || exit 1
                    sleep 0.1
                  done
                  if [ ! -S /tmp/.X11-unix/X98 ]; then
                    echo "Xvfb failed to start" >&2
                    exit 1
                  fi
                  # Invoked via the trap below; shellcheck does not count that as a call.
                  # shellcheck disable=SC2329
                  cleanup() {
                    kill "$xvfb_pid" 2>/dev/null || true
                  }
                  trap cleanup EXIT
                  node ${portal}/lib/node_modules/epicgames-freegames-node/src/index.ts
                '';
              };
              MemoryMax = "2G";
              UMask = "0077";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = "read-only";
              ReadWritePaths = [ stateDir ];
            };
          };
        };
      };
  };
}
