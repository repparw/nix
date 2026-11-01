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

        # Storefront automation runs as fgc with no access to bot secrets.
        # The root-only ExecStopPost notifier reports even failed runs.
        claimScript = pkgs.writeShellApplication {
          name = "free-games-claim";
          runtimeInputs = with pkgs; [
            coreutils
            nodejs-runtime
          ];
          text = ''
            state=/var/lib/free-games-claimer
            logs=$state/logs
            for store in epic-games gog; do
              printf 'pending\n' > "$logs/$store.status"
            done

            rc=0
            for store in epic-games gog; do
              echo "=== $store: run started $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
              if node ${claimer}/lib/node_modules/free-games-claimer/"$store".js >"$logs/$store.log" 2>&1; then
                printf '0\n' > "$logs/$store.status"
                echo "=== $store: run finished ==="
              else
                store_rc=$?
                printf '%s\n' "$store_rc" > "$logs/$store.status"
                rc=1
                echo "=== $store: run FAILED (exit $store_rc) ==="
              fi
              tail -n 5 "$logs/$store.log" || true
            done
            exit "$rc"
          '';
        };

        # The notifier runs as root so hermes-env remains inaccessible to the
        # unprivileged browser. The notification state is root-owned as well.
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
        # The container user maps 1:1 to a host uid (no privateUsers), so the
        # host-owned state directory is pre-created with the same numeric ids.
        systemd.tmpfiles.rules = [
          "d ${stateDir} 0755 root root - -"
        ];

        # nspawn --port exposes the endpoint on all host interfaces.
        # Instead, proxy localhost:6080 to the private container address.
        systemd.services.free-games-novnc-loopback = {
          description = "SSH-only loopback access to free-games-claimer noVNC";
          requires = [ "container@free-games-claimer.service" ];
          after = [ "container@free-games-claimer.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:6080,bind=127.0.0.1,reuseaddr,fork TCP:${config.containers.free-games-claimer.localAddress}:6080";
            Restart = "always";
            RestartSec = "5s";
          };
        };

        # Reject routed traffic, including traffic from other containers.
        # The host-to-container proxy uses OUTPUT and remains allowed.
        networking.firewall.extraForwardRules = ''
          ip daddr ${config.containers.free-games-claimer.localAddress} tcp dport 6080 drop
        '';

        containers.free-games-claimer = servicesLib.mkContainer {
          inherit cfg;
          name = "free-games-claimer";

          # No nspawn port forwarding. The host proxy binds to loopback only.

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
              time.timeZone = "America/Argentina/Buenos_Aires";

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
                "d /var/lib/free-games-claimer/data 0750 fgc fgc - -"
                "d /var/lib/free-games-claimer/logs 0750 fgc fgc - -"
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
                  ExecStart = "${pkgs.x11vnc}/bin/x11vnc -display :99 -localhost -forever -shared -nopw -rfbport 5900";
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
                  ExecStart = "${websockify}/bin/websockify --web ${novncStatic} ${config.containers.free-games-claimer.localAddress}:6080 127.0.0.1:5900";
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
                  FGC_DATA_DIR = "/var/lib/free-games-claimer/data";
                  FGC_CHROME_PATH = "${pkgs.chromium}/bin/chromium";
                };
                serviceConfig = {
                  Type = "oneshot";
                  User = "fgc";
                  ExecStart = "${claimScript}/bin/free-games-claim";
                  # '+' overrides User=fgc for this command only. Executed
                  # after success or failure (including ExecStart errors).
                  ExecStopPost = "+${notifyScript}/bin/free-games-notify";
                  # Chromium plus a slow store page can take a while on the pi.
                  TimeoutStartSec = "2h";
                };
                preStart = ''
                  state=/var/lib/free-games-claimer
                  mkdir -p "$state/data/browser" "$state/data/screenshots/epic-games/failed" "$state/data/screenshots/gog"
                  # A killed run can leave a stale Chromium profile lock.
                  rm -f "$state/data/browser/SingletonLock"
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
