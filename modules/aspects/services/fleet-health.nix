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
            gawk
            gnused
            coreutils
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

            # Alerts are per-check Discord messages: a check reaching two
            # strikes posts DOWN (a new message, so channel notifications
            # fire), and recovery DELETES that message — the channel only
            # ever shows what is currently down. The message id lives in
            # the dotfile .$n.msgid so counter globs never see it.
            alert_post() { # content -> message id (empty on failure)
              curl -s -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg c "$1" '{content: $c}')" "$api" \
                | jq -r '.id // empty'
            }

            alert_delete() { # message id
              curl -s -m 15 -o /dev/null -X DELETE \
                -H "Authorization: Bot $DISCORD_BOT_TOKEN" "$api/messages/$1" || true
            }

            failures=0

            fail() { # name, detail
              local n="$1" detail="$2" count mid
              if [ "$strict" = 1 ]; then
                failures=$((failures + 1))
                return
              fi
              count=$(( $(cat "$state_dir/$n" 2>/dev/null || echo 0) + 1 ))
              printf '%s\n' "$count" > "$state_dir/$n"
              if [ "$count" -ge 2 ] && [ ! -e "$state_dir/.$n.msgid" ]; then
                mid=$(alert_post ":red_circle: DOWN $n ($detail)")
                [ -n "$mid" ] && printf '%s\n' "$mid" > "$state_dir/.$n.msgid"
              fi
            }

            ok() { # name
              [ "$strict" = 1 ] && return
              local n="$1" mid
              if [ -e "$state_dir/.$n.msgid" ]; then
                mid=$(cat "$state_dir/.$n.msgid")
                alert_delete "$mid"
                rm -f "$state_dir/.$n.msgid"
              fi
              printf '0\n' > "$state_dir/$n"
            }

            # systemd units (pi-local). container@authelia and container@miniflux
            # live on epsilon now; their HTTP endpoints are checked above.
            # container@hermes moved to epsilon too and runs no HTTP endpoint;
            # its unit is monitored from epsilon's own checks.
            for u in \
              container@homeassistant container@archisteamfarm \
              traefik; do
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

            # Failed-unit sweep: catch any latched failed state, not just the
            # watchlist above. Monitoring only — never part of strict gates,
            # so a broken unit cannot block update flips. Noise control rides
            # the two-strike machinery per unit: a failure must persist
            # across two runs (>= 10 min) to alert once, and a failure that
            # clears between runs never alerts at all. The previous run's
            # failed set is tracked so recovered units get ok() (counter
            # reset + recovery notice) instead of stale counters.
            if [ "$strict" != 1 ]; then
              # systemd prefixes failed rows with a bullet on newer
              # versions; extract real unit names by their suffix.
              failed_cur=$(systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null \
                | grep -oE '[a-zA-Z0-9@._\\-]+\.(service|timer|mount|path|scope|socket|target)' | sort -u)
              failed_prev=$(cat "$state_dir/.failed-units" 2>/dev/null || true)

              for u in $failed_prev; do
                printf '%s\n' "$failed_cur" | grep -qx "$u" || ok "unit-failed:$u"
              done
              for u in $failed_cur; do
                fail "unit-failed:$u" "systemd failed state"
              done
              printf '%s\n' "$failed_cur" > "$state_dir/.failed-units"
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

            # authelia and miniflux are epsilon-hosted now: probe their
            # public vhosts through the real edge path. As cross-host
            # surfaces they are remote() checks — epsilon's health never
            # gates or rolls back pi's flip.
            remote authelia https://auth.repparw.com/api/health 200
            remote miniflux https://rss.repparw.com/healthcheck 200
            http home-assistant http://10.231.136.2:8123 ""
            # pi's own traefik still serves the LAN vhost for HA; the check
            # pins SNI to the local loopback per the sniStrict gotcha.
            http home https://home.repparw.com/ "" --resolve home.repparw.com:443:127.0.0.1
            remote apex https://repparw.com/ 200
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
            # as ghosts that keep failing the strict gate forever. Prune
            # them from $state_dir by hand when touching check names
            # (happened with unit:postgresql/unit:miniflux on the move).

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

  den.aspects.nixos-services.provides.coredump-watch = {
    nixos =
      {
        options,
        config,
        pkgs,
        lib,
        ...
      }:
      let
        cfg = config.modules.coredump-watch;

        # Same delivery contract as the probe: post via the Discord REST API
        # on the hermes bot token so the watcher never dies with hermes.
        channelId = "1515064288191053979";

        coredumpsScript = pkgs.writeShellApplication {
          name = "coredump-watch";
          runtimeInputs = with pkgs; [
            curl
            jq
            gawk
            gnused
            coreutils
            systemd
          ];
          text = ''
            state_dir=/var/lib/fleet-health
            mkdir -p "$state_dir"
            # Dotfile so the probe's counter glob never sees bookkeeping.
            marker="$state_dir/.coredumps-since"
            now=$(date +%s)

            # First run: establish the baseline and stay silent — a fresh
            # install must not replay crash history into the channel.
            if [ ! -e "$marker" ]; then
              printf '%s\n' "$now" > "$marker"
              echo "coredumps: baseline set, nothing reported"
              exit 0
            fi

            since=$(cat "$marker")
            printf '%s\n' "$now" > "$marker"

            # shellcheck disable=SC1091
            source /run/secrets/hermes-env
            api="https://discord.com/api/v10/channels/${channelId}/messages"
            notify() {
              curl -s -m 15 -X POST -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg c "$1" '{content: $c}')" "$api" >/dev/null || true
            }

            MUTE_JSON="''${MUTE_JSON:-[]}"
            entries=$(coredumpctl list --json=short --no-pager --since="@$since" 2>/dev/null || echo "[]")

            # Group new crashes by binary + signal; mute by basename so
            # known-noisy crashers are logged but never notified.
            report=$(printf '%s' "$entries" | jq -r --argjson mute "$MUTE_JSON" '
              [ .[]
                | select(.exe != null and .exe != "")
                | { base: (.exe | split("/") | last), sig: (.sig // "unknown") } ]
              | map(select((.base as $b | $mute | index($b)) | not))
              | sort_by(.base, .sig)
              | group_by([.base, .sig])
              | map("\(length)x \(.[0].base) (sig \(.[0].sig))")
              | .[]' 2>/dev/null || true)

            count=$(printf '%s\n' "$report" | grep -c . || true)
            if [ "$count" -gt 0 ]; then
              body=":warning: coredumps: $count new crash kind(s) on $HOSTNAME"
              while IFS= read -r line; do
                body+=$'\n'"• $line"
              done <<< "$report"
              notify "$body"
            else
              echo "coredumps: nothing new"
            fi

            muted=$(printf '%s' "$entries" | jq -r --argjson mute "$MUTE_JSON" '
              [ .[]
                | select(.exe != null and .exe != "")
                | (.exe | split("/") | last)
                | select(. as $b | $mute | index($b)) ] | length' 2>/dev/null || echo 0)
            [ "$muted" -gt 0 ] && echo "coredumps: $muted muted crash(es) suppressed"
          '';
        };
      in
      {
        options.modules.coredump-watch = {
          enable = lib.mkEnableOption "coredump surfacing to Discord (host-local; needs a persistent journal, so keep it off pi)";

          mute = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Executable basenames whose crashes are logged locally but never notified (known-noisy crashers)";
          };

          script = lib.mkOption {
            type = lib.types.package;
            readOnly = true;
            description = "coredump-watch package";
          };
        };

        config = {
          modules.coredump-watch.script = coredumpsScript;

          systemd.services.fleet-health-coredumps = lib.mkIf cfg.enable {
            description = "Surface new coredumps to Discord";
            after = [
              "network-online.target"
              "multi-user.target"
            ];
            wants = [ "network-online.target" ];
            environment = {
              HOSTNAME = config.networking.hostName;
              MUTE_JSON = builtins.toJSON cfg.mute;
            };
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe coredumpsScript;
              StateDirectory = "fleet-health";
            };
          };

          systemd.timers.fleet-health-coredumps = lib.mkIf cfg.enable {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*:0/15";
              Persistent = true;
            };
          };
        };
      };
  };
}
