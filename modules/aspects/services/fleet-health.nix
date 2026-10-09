{
  lib,
  pkgs,
  ...
}:
let
  discordNotifyText = ''
    if [ $# -lt 1 ]; then
      echo "usage: discord-notify post <content> | delete <message-id>" >&2
      exit 2
    fi
    cmd="$1"; shift

    # shellcheck disable=SC1091
    source /run/secrets/hermes-env
    if [ -z "''${DISCORD_BOT_TOKEN:-}" ]; then
      echo "discord-notify: DISCORD_BOT_TOKEN missing (hermes-env unreadable?)" >&2
      exit 1
    fi
    if [ -z "''${DISCORD_CHANNEL_ID:-}" ]; then
      echo "discord-notify: DISCORD_CHANNEL_ID not set" >&2
      exit 1
    fi
    api="https://discord.com/api/v10/channels/$DISCORD_CHANNEL_ID/messages"

    case "$cmd" in
      post)
        content="''${1:-}"
        resp=$(curl -s -m 15 -w '\n%{http_code}' -X POST \
          -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
          -H "Content-Type: application/json" \
          -d "$(jq -n --arg c "$content" '{content: $c}')" "$api" || true)
        code=$(printf '%s' "$resp" | tail -n 1)
        mid=$(printf '%s' "$resp" | sed '$d' | jq -r '.id // empty' 2>/dev/null || true)
        if [ -n "$mid" ]; then
          echo "discord-notify: posted msg $mid (http $code)" >&2
          printf '%s' "$mid"
        else
          echo "discord-notify: POST failed (http $code)" >&2
          exit 1
        fi
        ;;
      delete)
        id="''${1:-}"
        code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' -X DELETE \
          -H "Authorization: Bot $DISCORD_BOT_TOKEN" "$api/messages/$id" || echo curl-fail)
        case "$code" in
          200 | 204)
            echo "discord-notify: deleted msg $id (http $code)" >&2
            ;;
          # 404 Unknown Message means the message is already gone, which is the
          # state the caller asked for. Treating it as retryable pinned the
          # msgid file forever: every probe re-attempted a deletion that can
          # never succeed. Exiting zero lets the caller clear its own state.
          # A 5xx or a transport failure stays retryable, because the message
          # may well still be there.
          404)
            echo "discord-notify: msg $id already absent (http 404), treating as cleared" >&2
            ;;
          *)
            echo "discord-notify: DELETE failed: msg $id http=$code (msgid kept for retry)" >&2
            exit 1
            ;;
        esac
        ;;
      *)
        echo "usage: discord-notify post <content> | delete <message-id>" >&2
        exit 2
        ;;
    esac
  '';

  mkDiscordNotify =
    pkgs_:
    pkgs_.writeShellApplication {
      name = "discord-notify";
      runtimeInputs = with pkgs_; [
        curl
        jq
      ];
      text = discordNotifyText;
    };
in
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
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
        cfg = config.modules.services;
        vhostProbes = lib.concatStringsSep "\n" (
          map
            (
              name:
              let
                service = cfg.definitions.${name};
                fqdn = "${service.hostname}.${cfg.domain}";
              in
              if name == "homeassistant" then
                ''
                  http home-assistant ${servicesLib.serviceUrl cfg config name} ""
                  http home https://${fqdn}/ "" --resolve ${fqdn}:443:127.0.0.1''
              else if service.healthcheck != null then
                "            remote ${name} ${servicesLib.publicHealthUrl cfg config name} 200"
              else
                "            remote ${name} ${servicesLib.serviceUrl cfg config name}/ \"\""
            )
            (
              lib.sort (a: b: a < b) (
                lib.attrNames (lib.filterAttrs (_: service: (service.hostname or null) != null) cfg.definitions)
              )
            )
        );
        probeScript = pkgs.writeShellApplication {
          name = "fleet-health-probe";
          runtimeInputs = with pkgs; [
            curl
            (mkDiscordNotify pkgs)
            jq
            gawk
            gnused
            coreutils
            systemd
            openssh
            util-linux
            gnugrep
            config.modules.fleet-unit-state.snapshot
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

                        state_dir="''${STATE_DIRECTORY:-/var/lib/fleet-health}"
                        mkdir -p "$state_dir"


                        if [ "$strict" != 1 ]; then
                          exec 9>"$state_dir/.probe.lock"
                          flock 9
                        fi

                        failures=0

                        fail() {
                          local n="$1" detail="$2" count mid
                          if [ "$strict" = 1 ]; then
                            failures=$((failures + 1))
                            return
                          fi
                          count=$(( $(cat "$state_dir/$n" 2>/dev/null || echo 0) + 1 ))
                          printf '%s\n' "$count" > "$state_dir/$n"
                          if [ "$count" -ge 2 ] && [ ! -e "$state_dir/.$n.msgid" ]; then
                            mid=$(discord-notify post ":red_circle: DOWN $HOSTNAME $n ($detail)" || true)
                            [ -z "$mid" ] || printf '%s\n' "$mid" > "$state_dir/.$n.msgid"
                          fi
                        }

                        ok() {
                          [ "$strict" = 1 ] && return
                          local n="$1" mid
                          if [ -e "$state_dir/.$n.msgid" ]; then
                            mid=$(cat "$state_dir/.$n.msgid")
                            if discord-notify delete "$mid"; then
                              rm -f "$state_dir/.$n.msgid"
                            fi
                          fi
                          printf '0\n' > "$state_dir/$n"
                        }

                        for u in \
                          container@homeassistant \
                          traefik; do
                          if systemctl is-active --quiet "$u"; then ok "unit:$u"; else fail "unit:$u" "systemd inactive"; fi
                        done

                        if [ "$(systemctl is-failed restic-backups-offsite)" = failed ]; then
                          fail "unit:restic-backups-offsite" "oneshot failed"
                        else
                          ok "unit:restic-backups-offsite"
                        fi

                        sweep_units() {
                          local host="$1" current previous unit alert recovering="" prefix="unit-failed:$1:" previous_file="$state_dir/.failed-units-$1"
                          if [ "$host" = "$HOSTNAME" ]; then
                            prefix="unit-failed:"
                            previous_file="$state_dir/.failed-units"
                            if ! current=$(fleet-unit-snapshot); then
                              fail "host-units:$host" "failed-unit snapshot unavailable"
                              return 0
                            fi
                          else
                            if ! current=$(timeout 30 ssh \
                              -i /home/repparw/.ssh/id_ed25519 \
                              -o BatchMode=yes -o IdentitiesOnly=yes \
                              -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
                              "root@$2" fleet-unit-snapshot); then
                              fail "host-units:$host" "SSH failed-unit snapshot unavailable"
                              return 0
                            fi
                          fi
                          if printf '%s\n' "$current" | grep -vE '^$|^[a-zA-Z0-9@._:\\-]+\.(service|timer|mount|path|scope|socket|target|automount|slice|device|swap)$' >/dev/null; then
                            fail "host-units:$host" "invalid failed-unit snapshot"
                            return 0
                          fi
                          ok "host-units:$host"
                          previous=$(cat "$previous_file" 2>/dev/null || true)
                          for alert in "$state_dir/.$prefix"*.msgid; do
                            [ -f "$alert" ] || continue
                            unit="''${alert##*/}"
                            unit="''${unit#."$prefix"}"
                            unit="''${unit%.msgid}"
                            if [ "$host" = "$HOSTNAME" ]; then
                              case "$unit" in alpha:* | epsilon:*) continue ;; esac
                            fi
                            previous+=$'\n'"$unit"
                          done
                          previous=$(printf '%s\n' "$previous" | sed '/^$/d' | sort -u)
                          for unit in $previous; do
                            if ! printf '%s\n' "$current" | grep -xF -e "$unit" >/dev/null; then
                              ok "$prefix$unit"
                              if [ -e "$state_dir/.$prefix$unit.msgid" ]; then
                                recovering+="$unit"$'\n'
                              fi
                            fi
                          done
                          for unit in $current; do
                            fail "$prefix$unit" "systemd failure or retained job failure"
                          done
                          printf '%s\n' "$current" "$recovering" | sed '/^$/d' | sort -u > "$previous_file"
                        }

                        if [ "$strict" != 1 ]; then
                          sweep_units "$HOSTNAME"
                          if [ "$local_only" != 1 ]; then
                            ${lib.concatMapStringsSep "\n"
                              (host: "sweep_units ${lib.escapeShellArg host} ${lib.escapeShellArg cfg.hostAddresses.${host}}")
                              [
                                "alpha"
                                "epsilon"
                              ]
                            }
                          fi
                        fi

                        http() {
                          local n="$1" url="$2" want="$3"; shift 3
                          local code
                          code=$(curl -s -m 6 -o /dev/null -w '%{http_code}' "$@" "$url" || true)
                          if [ -n "$want" ]; then
                            if [ "$code" = "$want" ]; then ok "http:$n"; else fail "http:$n" "got $code want $want"; fi
                          else
                            if [ "$code" != 000 ]; then ok "http:$n"; else fail "http:$n" "no response"; fi
                          fi
                        }

                        remote() {
                          [ "$local_only" = 1 ] || http "$@"
                        }

            ${vhostProbes}
                        remote apex https://${cfg.domain}/ 200

                        if [ "$strict" = 1 ]; then
                          [ "$failures" -eq 0 ]
                          exit $?
                        fi

                        if [ -e /var/lib/auto-update/PAUSE ]; then
                          fail "auto-update-paused" "PAUSE flag present"
                        else
                          ok "auto-update-paused"
                        fi


                        exit 0
          '';
        };

        failureDropins = pkgs.symlinkJoin {
          name = "fleet-health-failure-dropins";
          paths = [
            (pkgs.writeTextDir "lib/systemd/system/service.d/90-fleet-health.conf" ''
              [Unit]
              OnFailure=fleet-health-event.service
            '')
            (pkgs.writeTextDir "lib/systemd/system/fleet-health-event.service.d/99-no-recursion.conf" ''
              [Unit]
              OnFailure=
            '')
          ];
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
          environment.systemPackages = [ probeScript ];

          systemd.services.fleet-health = {
            description = "Probe the fleet and alert on state changes";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            environment = {
              HOSTNAME = config.networking.hostName;
              DISCORD_CHANNEL_ID = config.modules.services.discordChannelId;
            };
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe probeScript;
              StateDirectory = "fleet-health";
            };
          };

          systemd.packages = [ failureDropins ];

          systemd.services.fleet-health-event = {
            description = "Confirm a systemd service failure through fleet health";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig.Type = "oneshot";
            script = ''
              systemctl start fleet-health.service || true
              sleep 60
              systemctl start fleet-health.service || true
            '';
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

        coredumpsScript = pkgs.writeShellApplication {
          name = "coredump-watch";
          runtimeInputs = [
            pkgs.python3
            pkgs.openssh
            pkgs.systemd
          ];
          text = ''
            exec python3 ${./coredump-watch/collector.py}
          '';
        };
      in
      {
        options.modules.coredump-watch = {
          enable = lib.mkEnableOption "coredump triage through Hermes (requires a persistent journal)";

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

          programs.ssh.knownHosts.hermes-crash-intake = lib.mkIf cfg.enable {
            hostNames = [ config.modules.services.hostSshAddresses.epsilon ];
            publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINE+UZW7+eImXJ4pM8P0onKRk9hNnEcJeBCpSv+GhPRy";
          };

          systemd.services.fleet-health-coredumps = lib.mkIf cfg.enable {
            description = "Queue new coredumps for Hermes investigation";
            after = [
              "network-online.target"
              "multi-user.target"
            ];
            wants = [ "network-online.target" ];
            environment = {
              HOSTNAME = config.networking.hostName;
              MUTE_JSON = builtins.toJSON cfg.mute;
              HERMES_TARGET = "root@${config.modules.services.hostSshAddresses.epsilon}";
              HERMES_SSH_IDENTITY = "/home/repparw/.ssh/id_ed25519";
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

  den.aspects.nixos-services.provides.disk-watch = {
    nixos =
      {
        options,
        config,
        pkgs,
        lib,
        ...
      }:
      let
        cfg = config.modules.disk-watch;

        diskWatchScript = pkgs.writeShellApplication {
          name = "disk-watch";
          runtimeInputs = with pkgs; [
            curl
            (mkDiscordNotify pkgs)
            jq
            gawk
            gnugrep
            coreutils
            btrfs-progs
          ];
          text = ''
            state_dir="$STATE_DIRECTORY"
            mkdir -p "$state_dir"

            slug() { printf '%s' "$1" | tr -c '[:alnum:]._-' '_'; }

            set_level() {
              local check="$1" level="$2" detail="$3" s mid prev
              s="$(slug "$check")"
              prev="ok"
              [ -f "$state_dir/$s.level" ] && prev="$(cat "$state_dir/$s.level")"
              if [ "$level" = "$prev" ]; then
                return 0
              fi
              if [ -f "$state_dir/.$s.msgid" ]; then
                mid="$(cat "$state_dir/.$s.msgid")"
                discord-notify delete "$mid" || true
                rm -f "$state_dir/.$s.msgid"
              fi
              if [ "$level" != "ok" ]; then
                if [ "$level" = "crit" ]; then
                  mid=$(discord-notify post ":red_circle: disk-space CRIT $HOSTNAME $check ($detail)" || true)
                else
                  mid=$(discord-notify post ":warning: disk-space warn $HOSTNAME $check ($detail)" || true)
                fi
                [ -n "$mid" ] && printf '%s\n' "$mid" > "$state_dir/.$s.msgid"
              fi
              printf '%s\n' "$level" > "$state_dir/$s.level"
            }

            level_for() {
              awk -v p="$1" -v w="$2" -v c="$3" 'BEGIN {
                if (p >= c) print "crit"; else if (p >= w) print "warn"; else print "ok"
              }'
            }

            MOUNTS_JSON="''${MOUNTS_JSON:-[]}"
            META_WARN="''${META_WARN:-85}"
            META_CRIT="''${META_CRIT:-93}"
            META_UNALLOC_WARN_GB="''${META_UNALLOC_WARN_GB:-10}"
            META_UNALLOC_CRIT_GB="''${META_UNALLOC_CRIT_GB:-2}"

            printf '%s' "$MOUNTS_JSON" | jq -c '.[]' | while IFS= read -r row; do
              mp=$(printf '%s' "$row" | jq -r '.mount')
              warn=$(printf '%s' "$row" | jq -r '.warn')
              crit=$(printf '%s' "$row" | jq -r '.crit')
              if [ ! -d "$mp" ]; then
                echo "disk-watch: $mp missing, skipping" >&2
                continue
              fi
              pct=$(df --output=pcent "$mp" | tail -n 1 | tr -d ' %')
              set_level "mount:$mp" "$(level_for "$pct" "$warn" "$crit")" "$mp at $pct% (warn>=$warn crit>=$crit)"

              # btrfs hides allocation pressure from df: a full metadata
              # pool ENOSPCs writes while data space still shows free, so
              # watch the metadata pool directly on btrfs mounts.
              if [ "$(stat -f -c %T "$mp")" = "btrfs" ]; then
                usage=$(btrfs filesystem usage "$mp" 2>/dev/null)
                meta_pct=$(printf '%s' "$usage" |
                  awk '/Metadata.*:/ {
                    if (match($0, /\([0-9.]+%\)/)) {
                      s = substr($0, RSTART+1, RLENGTH-2)
                      sub(/%$/, "", s)
                      print s
                    }
                  }' | head -n 1)
                # Raw metadata % hovers 70-90%+ on healthy pools. Gate on
                # whether the allocator can still grow: Sep 2026 was 97.7%
                # with ~0 unallocated while df looked fine.
                unalloc_gb=$(printf '%s' "$usage" |
                  awk '/Device unallocated:/ {
                    for (i=1; i<=NF; i++) if ($i ~ /^[0-9.]+(KiB|MiB|GiB|TiB)$/) { v=$i; break }
                    if (v ~ /KiB$/) { sub(/KiB$/, "", v); printf "%.2f", v/1048576 }
                    else if (v ~ /MiB$/) { sub(/MiB$/, "", v); printf "%.2f", v/1024 }
                    else if (v ~ /GiB$/) { sub(/GiB$/, "", v); printf "%.2f", v+0 }
                    else if (v ~ /TiB$/) { sub(/TiB$/, "", v); printf "%.2f", v*1024 }
                  }' | head -n 1)
                if [ -n "$meta_pct" ]; then
                  meta_lvl=$(awk -v p="$meta_pct" -v u="$unalloc_gb" \
                    -v w="$META_WARN" -v c="$META_CRIT" \
                    -v uw="$META_UNALLOC_WARN_GB" -v uc="$META_UNALLOC_CRIT_GB" 'BEGIN {
                    if (u == "") {
                      if (p+0 >= c+0) print "crit"; else if (p+0 >= w+0) print "warn"; else print "ok"
                    } else if (u+0 < uc+0) print "crit";
                    else if (p+0 >= w+0 && u+0 < uw+0) print "warn";
                    else print "ok"
                  }')
                  set_level "btrfs-meta:$mp" "$meta_lvl" "$mp metadata at $meta_pct% with ''${unalloc_gb:-unknown}GiB unallocated (warn>=$META_WARN% + <$META_UNALLOC_WARN_GB GiB unalloc, crit=<$META_UNALLOC_CRIT_GB GiB unalloc)"
                fi
              fi
            done
          '';
        };
      in
      {
        options.modules.disk-watch = {
          enable = lib.mkEnableOption "disk-space surfacing to Discord (posts on breach, deletes on recovery)";

          interval = lib.mkOption {
            type = lib.types.str;
            default = "*:0/15";
            description = "systemd OnCalendar for the disk-watch timer";
          };

          mounts = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  mount = lib.mkOption {
                    type = lib.types.str;
                    description = "Mountpoint to watch";
                  };
                  warn = lib.mkOption {
                    type = lib.types.int;
                    description = "Warn threshold in used percent";
                  };
                  crit = lib.mkOption {
                    type = lib.types.int;
                    description = "Critical threshold in used percent";
                  };
                };
              }
            );
            default = [ ];
            description = "Mounts to watch with warn/crit used-percent thresholds";
          };

          metadataWarn = lib.mkOption {
            type = lib.types.int;
            default = 85;
            description = "Warn threshold for btrfs metadata pool usage percent";
          };

          metadataCrit = lib.mkOption {
            type = lib.types.int;
            default = 93;
            description = "Critical threshold for btrfs metadata pool usage percent";
          };

          metadataUnallocWarnGiB = lib.mkOption {
            type = lib.types.int;
            default = 10;
            description = "Warn when btrfs metadata pool is over metadataWarn percent AND unallocated space drops below this many GiB";
          };

          metadataUnallocCritGiB = lib.mkOption {
            type = lib.types.int;
            default = 2;
            description = "Critical when btrfs unallocated space drops below this many GiB, regardless of metadata percent";
          };
        };

        config = {
          systemd.services.disk-watch = lib.mkIf cfg.enable {
            description = "Check disk space and alert to Discord on breach";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            environment = {
              HOSTNAME = config.networking.hostName;
              MOUNTS_JSON = builtins.toJSON cfg.mounts;
              DISCORD_CHANNEL_ID = config.modules.services.discordChannelId;
              META_WARN = toString cfg.metadataWarn;
              META_CRIT = toString cfg.metadataCrit;
              META_UNALLOC_WARN_GB = toString cfg.metadataUnallocWarnGiB;
              META_UNALLOC_CRIT_GB = toString cfg.metadataUnallocCritGiB;
            };
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe diskWatchScript;
              StateDirectory = "disk-watch";
            };
          };

          systemd.timers.disk-watch = lib.mkIf cfg.enable {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = cfg.interval;
              Persistent = true;
            };
          };
        };
      };
  };

  den.aspects.nixos-services.provides.reboot-watch = {
    nixos =
      {
        options,
        config,
        pkgs,
        lib,
        ...
      }:
      let
        cfg = config.modules.reboot-watch;

        rebootWatchScript = pkgs.writeShellApplication {
          name = "reboot-watch";
          runtimeInputs = with pkgs; [
            curl
            (mkDiscordNotify pkgs)
            jq
            coreutils
          ];
          text = ''
            state_dir="$STATE_DIRECTORY"
            mkdir -p "$state_dir"

            if ! booted=$(readlink /run/booted-system/{initrd,kernel,kernel-modules} 2>/dev/null); then
              echo "reboot-watch: cannot determine booted kernel/initrd state, skipping" >&2
              exit 0
            fi
            if ! built=$(readlink /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules} 2>/dev/null); then
              echo "reboot-watch: cannot determine staged kernel/initrd state, skipping" >&2
              exit 0
            fi

            if [ "$booted" = "$built" ]; then
              if [ -f "$state_dir/.reboot-required.msgid" ]; then
                mid="$(cat "$state_dir/.reboot-required.msgid")"
                if discord-notify delete "$mid"; then
                  rm -f "$state_dir/.reboot-required.msgid"
                fi
              fi
              echo "reboot-watch: converged"
            else
              if [ ! -f "$state_dir/.reboot-required.msgid" ]; then
                mid=$(discord-notify post ":arrows_counterclockwise: reboot-required $HOSTNAME (staged kernel/initrd differs from booted — reboot to converge)" || true)
                [ -n "$mid" ] && printf '%s\n' "$mid" > "$state_dir/.reboot-required.msgid"
              else
                echo "reboot-watch: still pending"
              fi
            fi
          '';
        };
      in
      {
        options.modules.reboot-watch = {
          enable = lib.mkEnableOption "reboot-required surfacing to Discord (posts on pending, deletes on convergence)";

          interval = lib.mkOption {
            type = lib.types.str;
            default = "*:0/15";
            description = "systemd OnCalendar for the reboot-watch timer";
          };
        };

        config = {
          systemd.services.reboot-watch = lib.mkIf cfg.enable {
            description = "Check for a pending kernel/initrd generation and alert to Discord";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            environment = {
              HOSTNAME = config.networking.hostName;
              DISCORD_CHANNEL_ID = config.modules.services.discordChannelId;
            };
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe rebootWatchScript;
              StateDirectory = "reboot-watch";
            };
          };

          systemd.timers.reboot-watch = lib.mkIf cfg.enable {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = cfg.interval;
              Persistent = true;
            };
          };
        };
      };
  };
}
