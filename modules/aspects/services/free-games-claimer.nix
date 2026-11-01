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
        container = true;
        backupRelativePath = "free-games-claimer";
      };
    };

    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
        claimer = pkgs.callPackage ../../_packages/free-games-claimer.nix { };
        claimDiff = pkgs.writeText "claim-diff.jq" (builtins.readFile ./free-games-claimer/claim-diff.jq);
        discordNotify = servicesLib.mkDiscordNotify pkgs config.modules.services.discordChannelId;
        stateDir = "${cfg.configDir}/free-games-claimer";

        # Runs both storefronts, then reports claimed/failed games and login or
        # captcha trouble through the fleet bot identity. Deliberately runs the
        # second store after the first one fails: a broken session on Epic must
        # not stop the GOG claim.
        claimScript = pkgs.writeShellApplication {
          name = "free-games-claim";
          runtimeInputs = with pkgs; [
            coreutils
            discordNotify
            gnugrep
            jq
            nodejs-runtime
          ];
          text = ''
            state=/var/lib/free-games-claimer
            app=$state/app
            data=$app/data
            logs=$state/logs
            mkdir -p "$logs"

            rc=0
            for store in epic-games gog; do
              echo "=== $store: run started $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
              if node "$app/$store.js" >"$logs/$store.log" 2>&1; then
                echo "=== $store: run finished ==="
              else
                rc=1
                echo "=== $store: run FAILED ==="
              fi
              tail -n 5 "$logs/$store.log" || true
            done

            prev='{}'
            if [ -s "$state/notify-state.json" ]; then
              prev=$(cat "$state/notify-state.json")
            fi
            epic='{}'
            if [ -s "$data/epic-games.json" ]; then
              epic=$(cat "$data/epic-games.json")
            fi
            gog='{}'
            if [ -s "$data/gog.json" ]; then
              gog=$(cat "$data/gog.json")
            fi

            diffout=$(jq -n \
              --argjson previous "$prev" \
              --argjson epic "$epic" \
              --argjson gog "$gog" \
              -f ${claimDiff})
            lines=$(jq -r '.lines | join("\n")' <<<"$diffout")

            msg="$lines"
            for store in epic-games gog; do
              if grep -q "Not signed in anymore" "$logs/$store.log" 2>/dev/null; then
                msg+=$'\n'"🔑 $store needs login: ssh -N -L 6080:127.0.0.1:6080 pi, then open http://localhost:6080/vnc.html and rerun the service"
              fi
              if grep -qi "captcha" "$logs/$store.log" 2>/dev/null; then
                msg+=$'\n'"⚠️ $store hit a captcha: open the VNC page above while a run is waiting, then rerun the service"
              fi
            done

            if [ -n "$msg" ]; then
              # Discord caps content at 2000 chars; keep a comfortable margin.
              msg=$(printf '%s' "$msg" | head -c 1900)
              discord-notify post "**free-games-claimer**"$'\n'"$msg"
            fi

            # Persist the notification state only after the post was accepted,
            # so a Discord outage replays the report instead of losing it.
            jq '.state' <<<"$diffout" >"$state/notify-state.json.new"
            mv "$state/notify-state.json.new" "$state/notify-state.json"

            exit "$rc"
          '';
        };
      in
      {
        # The container user maps 1:1 to a host uid (no privateUsers), so the
        # host-owned state directory is pre-created with the same numeric ids.
        systemd.tmpfiles.rules = [
          "d ${stateDir} 0755 348 348 - -"
        ];

        containers.free-games-claimer = servicesLib.mkContainer {
          inherit cfg;
          name = "free-games-claimer";

          # noVNC is exposed on the host only for the occasional interactive
          # login or captcha; reach it through an SSH tunnel from a desktop:
          #   ssh -N -L 6080:127.0.0.1:6080 pi
          forwardPorts = [
            {
              containerPort = 6080;
              hostPort = 6080;
              protocol = "tcp";
            }
          ];

          bindMounts = {
            "/var/lib/free-games-claimer" = {
              hostPath = stateDir;
              isReadOnly = false;
            };
            "/run/secrets/hermes-env" = {
              hostPath = config.sops.secrets."hermes-env".path;
              isReadOnly = true;
            };
          };

          extraConfig =
            { pkgs, ... }:
            let
              # Upstream's websockify test suite fails on this nixpkgs pin
              # (jwcrypto InvalidJWEKeyLength in its own test fixtures), which
              # is unrelated to the websocket bridge used here.
              websockify = pkgs.python3Packages.websockify.overridePythonAttrs (_: {
                doCheck = false;
              });
              # Only the static noVNC app is needed; the novnc package would
              # drag the broken websockify through its patch substitution.
              novncStatic = pkgs.fetchFromGitHub {
                owner = "novnc";
                repo = "noVNC";
                rev = "v1.7.0";
                hash = "sha256-vObaEjP8ZgA4a4bEYbSBsSTl6CfYa/B7qmghM+iVDnQ=";
              };
            in
            {
              users.users.fgc = {
                isSystemUser = true;
                uid = 348;
                group = "fgc";
                home = "/var/lib/free-games-claimer";
              };
              users.groups.fgc.gid = 348;

              # Chromium renders with software GL on the headless pi; missing
              # GL is what triggers Epic's hcaptcha (upstream issue #483).
              fonts.packages = with pkgs; [
                noto-fonts
                noto-fonts-color-emoji
              ];

              systemd.tmpfiles.rules = [
                "d /var/lib/free-games-claimer/logs 0755 fgc fgc - -"
              ];

              # The claimer always drives a headed browser (headless trips
              # captchas), so a virtual display runs permanently and doubles
              # as the noVNC view for manual logins.
              systemd.services.free-games-display = {
                description = "Xvfb display for the free-games-claimer browser";
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  User = "fgc";
                  ExecStart = "${pkgs.xorg-server}/bin/Xvfb :99 -ac -screen 0 1920x1080x24 -nolisten tcp";
                  Restart = "always";
                  RestartSec = "5s";
                };
              };

              systemd.services.free-games-vnc = {
                description = "VNC server for the free-games-claimer display";
                requires = [ "free-games-display.service" ];
                after = [ "free-games-display.service" ];
                wantedBy = [ "free-games-display.service" ];
                serviceConfig = {
                  User = "fgc";
                  ExecStart = "${pkgs.x11vnc}/bin/x11vnc -display :99 -forever -shared -nopw -rfbport 5900";
                  Restart = "always";
                  RestartSec = "5s";
                };
              };

              systemd.services.free-games-novnc = {
                description = "noVNC websocket bridge for the free-games-claimer display";
                requires = [ "free-games-vnc.service" ];
                after = [ "free-games-vnc.service" ];
                wantedBy = [ "free-games-vnc.service" ];
                serviceConfig = {
                  User = "fgc";
                  ExecStart = "${websockify}/bin/websockify --web ${novncStatic} 6080 127.0.0.1:5900";
                  Restart = "always";
                  RestartSec = "5s";
                };
              };

              systemd.services.free-games-claimer = {
                description = "Claim free games on Epic and GOG";
                requires = [ "free-games-display.service" ];
                after = [
                  "free-games-display.service"
                  "network-online.target"
                ];
                wantedBy = [ ];
                environment = {
                  DISPLAY = ":99";
                  WIDTH = "1920";
                  HEIGHT = "1080";
                  TIMEOUT = "90";
                  LOGIN_TIMEOUT = "600";
                  NOVNC_PORT = "6080";
                  HOME = "/var/lib/free-games-claimer";
                  FGC_CHROME_PATH = "${pkgs.chromium}/bin/chromium";
                };
                serviceConfig = {
                  Type = "oneshot";
                  User = "fgc";
                  ExecStart = "${claimScript}/bin/free-games-claim";
                  # Chromium plus a slow store page can take a while on the pi.
                  TimeoutStartSec = "2h";
                };
                preStart = ''
                  state=/var/lib/free-games-claimer
                  marker=$state/.app-version
                  current=$(cat "$marker" 2>/dev/null || true)
                  if [ "$current" != "${claimer}" ]; then
                    tmp=$state/app.new
                    rm -rf "$tmp"
                    cp -r ${claimer}/lib/node_modules/free-games-claimer "$tmp"
                    rm -rf "$tmp/node_modules"
                    ln -s ${claimer}/lib/node_modules/free-games-claimer/node_modules "$tmp/node_modules"
                    if [ -d "$state/app/data" ]; then
                      mv "$state/app/data" "$tmp/data"
                    fi
                    rm -rf "$state/app.old"
                    if [ -d "$state/app" ]; then
                      mv "$state/app" "$state/app.old"
                    fi
                    mv "$tmp" "$state/app"
                    rm -rf "$state/app.old"
                    printf '%s\n' "${claimer}" >"$marker"
                  fi
                  mkdir -p "$state/app/data"
                  # A killed run leaves a stale profile lock that makes the
                  # next launch time out (upstream docker-entrypoint fix).
                  rm -f "$state/app/data/browser/SingletonLock"
                '';
              };

              systemd.timers.free-games-claimer = {
                description = "Run the free-games claimer daily";
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  # 18:10 ART is 21:10 UTC: comfortably after Epic's 16:00 UTC
                  # Friday rotation, with a same-evening retry for failures.
                  OnCalendar = "*-*-* 18:10:00";
                  Persistent = true;
                  RandomizedDelaySec = "30min";
                };
              };
            };
        };

        # systemd.nspawn's [Exec] has no MemoryMax/TasksMax keys.
        systemd.services."container@free-games-claimer".serviceConfig = {
          MemoryMax = "3G";
          TasksMax = 1024;
        };
      };
  };
}
