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
        portalStart = pkgs.writeShellApplication {
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
            node ${portal}/share/epicgames-freegames-node/src/index.ts
          '';
        };
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
            # Discord action links must resolve from other devices on the LAN.
            # Keep the portal on the Pi; do not expose it through the public edge.
            webPortalConfig = {
              baseUrl = "http://${cfg.hostAddresses.pi}:3000";
              listenOpts = {
                host = "0.0.0.0";
                port = 3000;
              };
            };
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
          # Allow the short-lived device-auth redirects from trusted LAN clients.
          # The Discord relay on 127.0.0.1:3999 remains loopback-only.
          networking.firewall.extraInputRules = ''
            iifname "eth0" ip saddr 192.168.0.0/24 tcp dport 3000 accept comment "LAN Epic device-auth portal"
          '';

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

          # claabs v6 is run-once: it starts its web server, redeems every
          # account, closes the server, and exits. The web portal therefore
          # only listens while a pass is active, so device-auth links sent in
          # the same pass resolve on the LAN and later ones wait for the next
          # run. Detection is scheduled 4x/day like upstream's default, off
          # set from the claimer's 18:10 GOG slot.
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
              Type = "oneshot";
              User = "epicfgc";
              Group = "epicfgc";
              ExecStart = lib.getExe portalStart;
              MemoryMax = "2G";
              UMask = "0077";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = "read-only";
              ReadWritePaths = [ stateDir ];
            };
          };

          systemd.timers.epic-freegames-portal = {
            description = "Run the Epic free-games device-auth portal";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*-*-* 00,06,12,18:40:00";
              Persistent = true;
              RandomizedDelaySec = "10min";
            };
          };
        };
      };
  };
}
