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
            jq
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
            # Dotfile so the counter glob below never sees bookkeeping.
            board_id_file="$state_dir/.board-msg-id"
            rm -f "$state_dir/board-msg-id"
            # shellcheck disable=SC1091
            source /run/secrets/hermes-env
            api="https://discord.com/api/v10/channels/${channelId}/messages"

            notify() {
              curl -s -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"content\":\"$1\"}" "$api" >/dev/null || true
            }

            # Status board: one Discord message edited in place, its id kept
            # in $board_id_file so edits never re-ping the channel.
            board_req() { # method, path, json-body-or-empty
              curl -s -m 15 -X "$1" \
                -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
                -H "Content-Type: application/json" \
                ''${3:+-d "$3"} "$api$2"
            }

            edit_board() { # content
              local bid
              bid=$(cat "$board_id_file" 2>/dev/null || true)
              if [ -n "$bid" ]; then
                if board_req PATCH "/messages/$bid" "$(jq -n --arg c "$1" '{content: $c}')" | grep -q '"id"'; then return; fi
              fi
              bid=$(board_req POST "" "{\"content\":\"$1\"}" | jq -r '.id // empty')
              if [ -n "$bid" ]; then printf '%s\n' "$bid" > "$board_id_file"; fi
            }

            delete_msg() {
              board_req DELETE "/messages/$1" >/dev/null || true
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

            # systemd units (pi-local). container@glance lives on epsilon
            # since the phase 2 dashboard migration; http probes follow the
            # same rule as backends move off this host.
            for u in \
              container@hermes container@homeassistant container@authelia \
              container@archisteamfarm \
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
            # Apex lives on epsilon since phase 2; resolve through its
            # public address so this exercises the real edge path.
            http apex https://repparw.com/ 200 
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

            # Board reflects the current down-set (2+ strikes) and only
            # exists while something is down; deleted on full recovery.
            # NOTE: renaming/removing a check leaves its counter files here
            # as ghosts that reappear in the down-set forever. Prune them
            # from $state_dir by hand when touching check names (happened
            # with unit:postgresql/unit:miniflux on the container move).
            # The trailing || true matters: with errexit+pipefail a healthy
            # fleet makes the while body's last test fail ([ 0 -ge 2 ]) and
            # kills the probe exactly when there is nothing to report.
            down=""
            for f in "$state_dir"/*; do
              [ -f "$f" ] || continue
              c=$(cat "$f" 2>/dev/null || true)
              if [ -n "$c" ] && [ "$c" -ge 2 ] 2>/dev/null; then
                down+="$(basename "$f" | sed 's/:/ /') "
              fi
            done
            down="''${down% }"
            if [ -n "$down" ]; then
              edit_board ":red_circle: fleet: down ->''${down% }"
            else
              bid=$(cat "$board_id_file" 2>/dev/null || true)
              if [ -n "$bid" ]; then delete_msg "$bid"; rm -f "$board_id_file"; fi
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
