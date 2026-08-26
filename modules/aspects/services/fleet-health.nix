{
  lib,
  pkgs,
  ...
}:
{
  den.aspects.nixos-services.provides.fleet-health = {
    nixos =
      {
        options,
        config,
        pkgs,
        ...
      }:
      let
        # Delivery rides the existing bot token: the probe must not die with
        # the thing it monitors, so it posts via the Discord REST API
        # directly instead of going through the hermes container.
        channelId = "1515064288191053979";

        probeScript = pkgs.writeShellApplication {
          name = "fleet-health-probe";
          runtimeInputs = with pkgs; [
            curl
            systemd
          ];
          text = ''
            usage="usage: fleet-health-probe [--strict] [--local]"

            strict=0
            local_only=0
            for a in "$@"; do
              case "$a" in
                --strict) strict=1 ;;
                --local) local_only=1 ;;
                *)
                  echo "$usage" >&2
                  exit 2
                  ;;
              esac
            done

            state_dir=/var/lib/fleet-health
            mkdir -p "$state_dir"
            # shellcheck disable=SC1091
            source /run/secrets/hermes-env
            api="https://discord.com/api/v10/channels/${channelId}/messages"

            notify() {
              curl -s -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"content\":\"$1\"}" "$api" >/dev/null || true
            }

            failures=0

            # Monitoring mode: two-strike counter files plus alert-once and
            # recovery notices. Strict mode (gates): silent, count only.
            fail() { # name, detail
              local n="$1" detail="$2" count
              if [ "$strict" = 1 ]; then
                failures=$((failures + 1))
                return
              fi
              count=$(( $(cat "$state_dir/$n" 2>/dev/null || echo 0) + 1 ))
              printf '%s\n' "$count" > "$state_dir/$n"
              if [ "$count" -ge 2 ] && [ ! -e "$state_dir/$n.alerted" ]; then
                notify ":red_circle: DOWN $n ($detail) — $count consecutive failures"
                touch "$state_dir/$n.alerted"
              fi
            }

            ok() { # name
              local n="$1"
              if [ "$strict" = 1 ]; then return; fi
              if [ -e "$state_dir/$n.alerted" ]; then
                notify ":green_circle: UP $n — recovered"
                rm -f "$state_dir/$n.alerted"
              fi
              printf '0\n' > "$state_dir/$n"
            }

            # systemd units (pi-local)
            for u in \
              container@hermes container@homeassistant container@authelia \
              container@glance container@archisteamfarm \
              container@miniflux traefik; do
              if systemctl is-active --quiet "$u"; then ok "unit:$u"; else fail "unit:$u" "systemd inactive"; fi
            done

            # Oneshots are inactive between runs by design: healthy means
            # "not failed". Excluded from strict gates on purpose — a broken
            # backup job must not block updates, monitoring still alerts.
            if [ "$(systemctl is-failed restic-backups-offsite)" = failed ]; then
              fail "unit:restic-backups-offsite" "oneshot failed"
            else
              ok "unit:restic-backups-offsite"
            fi

            # http probes: alive = any response; strict = exact code required
            http() { # name, url, strict_code_or_empty, extra_curl_args...
              local n="$1" url="$2" want="$3"; shift 3
              local code
              code=$(curl -s -m 6 -o /dev/null -w '%{http_code}' "$@" "$url" || true)
              if [ -n "$want" ]; then
                if [ "$code" = "$want" ]; then ok "http:$n"; else fail "http:$n" "got $code want $want"; fi
              else
                if [ "$code" != 000 ]; then ok "http:$n"; else fail "http:$n" "no response"; fi
              fi
            }

            # Cross-host surfaces live on alpha: skipped under --local so an
            # unrelated alpha outage can never gate or roll back pi's flip.
            remote() {
              [ "$local_only" = 1 ] || http "$@"
            }

            http authelia http://10.231.136.7:9091/api/health 200
            http miniflux http://10.231.136.16:8081/healthcheck 200
            http home-assistant http://10.231.136.2:8123 ""
            http glance http://10.231.136.15:8080 ""
            http apex https://repparw.com/ 200 --resolve repparw.com:443:127.0.0.1
            http rss https://rss.repparw.com/ "" --resolve rss.repparw.com:443:127.0.0.1
            remote jellyfin http://192.168.0.18:8096/ ""
            remote qbittorrent http://192.168.0.18:18080/ ""
            remote bazarr http://192.168.0.18:6767/ ""
            remote prowlarr http://192.168.0.18:9696/ ""
            remote radarr http://192.168.0.18:7878/ ""
            remote sonarr http://192.168.0.18:8989/ ""
            remote paperless http://192.168.0.18:8000/ ""
            remote finance http://192.168.0.18:3000/ ""

            if [ "$strict" = 1 ]; then
              [ "$failures" -eq 0 ]
              exit $?
            fi

            # Automation observability: a paused updater must never rot
            # silently. Monitoring mode only, so gates ignore it.
            if [ -e /var/lib/auto-update/PAUSE ]; then
              fail "auto-update-paused" "PAUSE flag present"
            else
              ok "auto-update-paused"
            fi

            exit 0
          '';
        };
      in
      {
        options.modules.fleet-health.probe = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "fleet-health-probe package; flags: --strict exits nonzero on any failure, --local skips cross-host probes";
        };

        config = {
          modules.fleet-health.probe = probeScript;

          systemd.services.fleet-health = {
            description = "Probe the fleet and alert on state changes";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe probeScript;
              StateDirectory = "fleet-health";
            };
          };

          systemd.timers.fleet-health = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*:0/5";
              Persistent = true;
            };
          };
        };
      };
  };
}
