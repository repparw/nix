{
  lib,
  pkgs,
  ...
}:
let
  mkDiscordNotify = (import ../../_services/lib.nix { inherit lib pkgs; }).mkDiscordNotify;
in
{
  den.aspects.nixos-services.provides.fleet-health = {
    nixos =
      {
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
                "            remote \"${service.host} epsilon\" ${name} ${
                              servicesLib.publicHealthUrl cfg config name
                            } 200"
              else if service.container && service.host != cfg.hostName then
                "container_http ${
                  lib.escapeShellArg cfg.hostAddresses.${service.host}
                } ${lib.escapeShellArg name} ${toString service.port}"
              else
                "            remote ${service.host} ${name} ${servicesLib.serviceUrl cfg config name}/ \"\""
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
            coreutils
            systemd
            openssh
            config.modules.fleet-unit-state.snapshot
          ];
          text = ''
            strict=0
            local_only=0
            for arg in "$@"; do
              case "$arg" in
                --strict) strict=1 ;;
                --local) local_only=1 ;;
                *) echo "usage: fleet-health-probe [--strict] [--local]" >&2; exit 2 ;;
              esac
            done

            failures=0
            fail() {
              echo "$1: $2" >&2
              failures=$((failures + 1))
            }

            for unit in container@homeassistant traefik; do
              if ! systemctl is-active --quiet "$unit"; then
                fail "$unit" "systemd inactive"
              fi
            done
            if [ "$(systemctl is-failed restic-backups-offsite)" = failed ]; then
              fail restic-backups-offsite "oneshot failed"
            fi

            check_units() {
              local host="$1" address="$2" current
              if [ "$host" = "${config.networking.hostName}" ]; then
                if ! current=$(fleet-unit-snapshot); then
                  fail "$host" "failed-unit snapshot unavailable"
                  return
                fi
              elif ! current=$(timeout 30 ssh \
                -i /home/repparw/.ssh/id_ed25519 \
                -o BatchMode=yes -o IdentitiesOnly=yes \
                -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
                "root@$address" fleet-unit-snapshot); then
                fail "$host" "failed-unit snapshot unavailable"
                return
              fi
              if [ -n "$current" ]; then
                fail "$host" "$current"
              fi
            }

            if [ "$strict" != 1 ]; then
              check_units ${lib.escapeShellArg config.networking.hostName} ""
              if [ "$local_only" != 1 ]; then
                ${lib.concatMapStringsSep "\n"
                  (host: "check_units ${lib.escapeShellArg host} ${lib.escapeShellArg cfg.hostAddresses.${host}}")
                  [
                    "alpha"
                    "epsilon"
                  ]
                }
              fi
              if [ -e /var/lib/auto-update/PAUSE ]; then
                fail auto-update "automation paused"
              fi
            fi

            http() {
              local name="$1" url="$2" want="$3" code
              shift 3
              code=$(curl -s -m 6 -o /dev/null -w '%{http_code}' "$@" "$url" || true)
              if [ -n "$want" ]; then
                if [ "$code" != "$want" ]; then fail "$name" "got $code want $want"; fi
              elif [ "$code" = 000 ]; then
                fail "$name" "no response"
              fi
            }
            remote() {
              local name="$2"
              shift 2
              [ "$local_only" = 1 ] && return 0
              http "$name" "$@"
            }
            container_http() {
              local address="$1" name="$2" port="$3" code
              [ "$local_only" = 1 ] && return 0
              if ! code=$(timeout 20 ssh \
                -i /home/repparw/.ssh/id_ed25519 \
                -o BatchMode=yes -o IdentitiesOnly=yes \
                -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
                "root@$address" bash -s -- "$name" "$port" <<'PROBE'
            set -eu
            address=$(nixos-container show-ip "$1")
            curl -s --max-time 6 -o /dev/null -w '%{http_code}' "http://$address:$2/"
            PROBE
              ); then
                fail "$name" "private backend probe failed"
                return 0
              fi
              case "$code" in
                200 | 301 | 302 | 303 | 307 | 308 | 401 | 403) ;;
                *) fail "$name" "private backend returned $code" ;;
              esac
            }
            ${vhostProbes}
            if [ "$strict" != 1 ] && [ "$local_only" != 1 ]; then
              http grafana-cloud ${config.modules.monitoring.cloudUrl}/api/health 200
            fi
            remote epsilon apex https://${cfg.domain}/ 200
            [ "$failures" -eq 0 ]
          '';
        };
      in
      {
        options.modules.fleet-health.probe = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "Read-only fleet-health-probe; --strict checks deployment readiness, --local skips cross-host probes";
        };
        config = {
          modules.fleet-health.probe = probeScript;
          environment.systemPackages = [ probeScript ];
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

  den.aspects.nixos-services.provides.free-model-watch = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.modules.free-model-watch;

        freeModelWatch = pkgs.writeShellApplication {
          name = "free-model-watch";
          runtimeInputs = with pkgs; [
            curl
            jq
            coreutils
            gnugrep
            gnused
            (mkDiscordNotify pkgs config.modules.services.discordChannelId)
          ];
          text = ''
            # The catalogues are plain text names that get sorted, diffed and
            # re-read, so the collation must be pinned here instead of being
            # inherited from the unit. systemd hands services the host locale
            # (alpha: LANG=en_IE.UTF-8, LC_MONETARY=es_AR.UTF-8, no LC_ALL), and
            # comm validates its inputs against LC_COLLATE: a snapshot recorded
            # in C order then reads as "not in sorted order" (en_IE orders
            # nemotron-3.5-... before nemotron-3-...), comm exits 1 and, with
            # pipefail + errexit, so does the whole service -- every run, with
            # the snapshot never moving. LC_ALL is not part of the locale
            # environment, so this has to be set by the script itself.
            export LC_ALL=C

            state_dir="''${STATE_DIRECTORY:-/var/lib/free-model-watch}"
            mkdir -p "$state_dir"

            opencode_url="''${OPENCODE_MODELS_URL:-https://opencode.ai/zen/v1/models}"
            nous_url="''${NOUS_MODELS_URL:-https://portal.nousresearch.com/api/nous/recommended-models}"

            fetch_opencode() {
              curl -fsS -m 20 "$opencode_url" 2>/dev/null |
                jq -r '.data[]?.id | select(endswith("-free"))' 2>/dev/null |
                sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u || true
            }

            fetch_nous() {
              curl -fsS -m 20 "$nous_url" 2>/dev/null |
                jq -r '.freeRecommendedModels[]?.modelName' 2>/dev/null |
                sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u || true
            }

            # Bounded so one churny catalog cannot blow past Discord's
            # per-message limit.
            compact() {
              sed '/^[[:space:]]*$/d' | sed -n '1,8p' | tr '\n' ' ' |
                sed 's/[[:space:]]*$//; s/[[:space:]]\{1,\}/, /g' | cut -c 1-400
            }

            parts=""
            changed=0

            # Snapshots only move into place after a successful announcement:
            # a Discord outage must not swallow the change, and the failed
            # unit is reported by the Cloud failed-jobs alert.
            stage=$(mktemp -d "$state_dir/.stage.XXXXXX")
            trap 'rm -rf "$stage"' EXIT

            record_source() {
              local name="$1" current="$2"
              local state_file previous added removed part
              state_file="$state_dir/$name.list"
              if [ -z "$current" ]; then
                echo "free-model-watch: $name catalog unavailable; keeping the previous snapshot" >&2
                return 0
              fi
              if [ ! -f "$state_file" ]; then
                printf '%s\n' "$current" > "$state_file"
                echo "free-model-watch: $name baseline recorded ($(printf '%s\n' "$current" | grep -c .) models)"
                return 0
              fi
              # Both sides must be collated the same way; LC_ALL=C is pinned for
              # the script and repeated here so the pair stays correct on its own.
              previous=$(sed '/^[[:space:]]*$/d' "$state_file" | LC_ALL=C sort -u)
              added=$(LC_ALL=C comm -13 <(printf '%s\n' "$previous") <(printf '%s\n' "$current") | sed '/^[[:space:]]*$/d')
              removed=$(LC_ALL=C comm -23 <(printf '%s\n' "$previous") <(printf '%s\n' "$current") | sed '/^[[:space:]]*$/d')
              if [ -z "$added" ] && [ -z "$removed" ]; then
                echo "free-model-watch: $name unchanged"
                return 0
              fi
              printf '%s\n' "$current" > "$stage/$name.list"
              part="• $name:"
              if [ -n "$added" ]; then
                part="$part new: $(printf '%s\n' "$added" | compact)"
              fi
              if [ -n "$removed" ]; then
                if [ -n "$added" ]; then
                  part="$part;"
                fi
                part="$part gone: $(printf '%s\n' "$removed" | compact)"
              fi
              parts="$parts
            $part"
              changed=1
            }

            record_source "opencode-free" "$(fetch_opencode)"
            record_source "nous-free" "$(fetch_nous)"

            if [ "$changed" = 0 ]; then
              echo "free-model-watch: no free-model catalog change"
              exit 0
            fi

            if [ -f "$state_dir/.free-models.msgid" ]; then
              previous_mid=$(cat "$state_dir/.free-models.msgid")
              if discord-notify delete "$previous_mid"; then
                rm -f "$state_dir/.free-models.msgid"
              fi
            fi

            if ! mid=$(discord-notify post ":eyes: free-model catalog changed on $HOSTNAME$parts") || [ -z "$mid" ]; then
              echo "free-model-watch: announcing the catalog change failed; snapshots kept" >&2
              exit 1
            fi

            for staged in "$stage"/*.list; do
              [ -f "$staged" ] || continue
              mv "$staged" "$state_dir/"
            done
            printf '%s\n' "$mid" > "$state_dir/.free-models.msgid"
            echo "free-model-watch: catalog change posted ($mid)"

            exit 0
          '';
        };
      in
      {
        options.modules.free-model-watch = {
          enable = lib.mkEnableOption "Discord notification when the OpenCode/Nous free-model catalogs change";

          interval = lib.mkOption {
            type = lib.types.str;
            default = "*-*-* 00/2:17:00";
            description = "systemd OnCalendar for the free-model-watch timer";
          };

          script = lib.mkOption {
            type = lib.types.package;
            readOnly = true;
            description = "free-model-watch package";
          };
        };

        config = {
          modules.free-model-watch.script = freeModelWatch;

          systemd.services.free-model-watch = lib.mkIf cfg.enable {
            description = "Notify Discord when free-tier model catalogs change";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            environment = {
              HOSTNAME = config.networking.hostName;
              DISCORD_CHANNEL_ID = config.modules.services.discordChannelId;
            };
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe freeModelWatch;
              StateDirectory = "free-model-watch";
            };
          };

          systemd.timers.free-model-watch = lib.mkIf cfg.enable {
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
