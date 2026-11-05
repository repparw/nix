{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.free-games-claimer = {
    service-registry = {
      name = "free-games-claimer";
      definition = {
        auth = "bypass";
        backupRelativePath = "free-games-claimer";
      };
    };

    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
        stateDir = "${cfg.configDir}/free-games-claimer";
        claimer = pkgs.callPackage ../../_packages/free-games-claimer.nix { };
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
        discordNotify = servicesLib.mkDiscordNotify pkgs cfg.discordChannelId;
        claimDiff = pkgs.writeText "claim-diff.jq" (builtins.readFile ./free-games-claimer/claim-diff.jq);

        # Xvfb and VNC exist only while a claim is running. SSH can forward
        # localhost:5900 for initial authentication and occasional captchas.
        claimScript = pkgs.writeShellApplication {
          name = "free-games-claim";
          runtimeInputs = with pkgs; [
            coreutils
            nodejs-runtime
            xorg-server
            x11vnc
          ];
          text = ''
            state=${lib.escapeShellArg stateDir}
            logs="$state/logs"
            export DISPLAY=:99 SHOW=1

            for store in epic-games gog; do
              printf 'pending\n' > "$logs/$store.status"
            done

            Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp &
            xvfb_pid=$!
            vnc_pid=
            cleanup() {
              if [ -n "$vnc_pid" ]; then
                kill "$vnc_pid" 2>/dev/null || true
              fi
              kill "$xvfb_pid" 2>/dev/null || true
            }
            trap cleanup EXIT

            for _ in $(seq 1 50); do
              [ -S /tmp/.X11-unix/X99 ] && break
              kill -0 "$xvfb_pid" 2>/dev/null || exit 1
              sleep 0.1
            done
            if [ ! -S /tmp/.X11-unix/X99 ]; then
              echo "Xvfb failed to start" >&2
              exit 1
            fi

            x11vnc -display :99 -localhost -forever -shared -nopw -rfbport 5900 -quiet &
            vnc_pid=$!

            rc=0
            for store in epic-games gog; do
              echo "=== $store: run started ==="
              if node ${claimer}/lib/node_modules/free-games-claimer/"$store".js >"$logs/$store.log" 2>&1; then
                printf '0\n' > "$logs/$store.status"
              else
                store_rc=$?
                printf '%s\n' "$store_rc" > "$logs/$store.status"
                rc=1
                echo "=== $store: failed (exit $store_rc) ==="
              fi
              tail -n 5 "$logs/$store.log" || true
            done
            exit "$rc"
          '';
        };

        # The browser user never receives the fleet Discord token.
        notifyScript = pkgs.writeShellApplication {
          name = "free-games-notify";
          runtimeInputs = with pkgs; [
            coreutils
            discordNotify
            gnugrep
            jq
          ];
          text = ''
            export FGC_CLAIM_DIFF=${claimDiff}
            ${builtins.readFile ./free-games-claimer/notify.sh}
          '';
        };
      in
      {
        users.groups.fgc.gid = 348;
        users.users.fgc = {
          isSystemUser = true;
          uid = 348;
          group = "fgc";
          home = stateDir;
        };

        systemd.tmpfiles.rules = [
          "d ${stateDir} 0700 fgc fgc - -"
          "d ${stateDir}/data 0700 fgc fgc - -"
          "d ${stateDir}/logs 0700 fgc fgc - -"
        ];

        fonts.packages = with pkgs; [
          noto-fonts
          noto-fonts-color-emoji
        ];

        systemd.services.free-games-claimer = {
          description = "Claim free games on Epic and GOG";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          environment = {
            HOME = stateDir;
            FGC_STATE_DIR = stateDir;
            FGC_DATA_DIR = "${stateDir}/data";
            FGC_CHROME_PATH = "${pkgs.chromium}/bin/chromium";
            SHOW = "1";
            WIDTH = "1920";
            HEIGHT = "1080";
            TIMEOUT = "90";
            LOGIN_TIMEOUT = "600";
          };
          preStart = ''
            mkdir -p "$FGC_DATA_DIR/browser" "$FGC_DATA_DIR/screenshots/epic-games/failed" "$FGC_DATA_DIR/screenshots/gog"
            rm -f "$FGC_DATA_DIR/browser/SingletonLock"
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "fgc";
            Group = "fgc";
            ExecStart = "${claimScript}/bin/free-games-claim";
            # A root-only post-stop hook handles both successes and failures.
            ExecStopPost = "+${notifyScript}/bin/free-games-notify";
            TimeoutStartSec = "2h";
            MemoryMax = "3G";
            TasksMax = 1024;
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = "read-only";
            ReadWritePaths = [ stateDir ];
          };
        };

        systemd.timers.free-games-claimer = {
          description = "Run the free-games claimer daily";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            # The Pi host already uses America/Argentina/Buenos_Aires.
            OnCalendar = "*-*-* 18:10:00";
            Persistent = true;
            RandomizedDelaySec = "30min";
          };
        };
      };
  };
}
