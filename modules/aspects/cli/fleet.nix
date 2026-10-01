{ den, lib, ... }:
let
  sshAddresses = lib.mapAttrs (_: host: host.sshAddress or host.serviceAddress) (
    lib.concatMapAttrs (_system: hosts: hosts) den.hosts
  );
  hostNames = lib.attrNames sshAddresses;
in
{
  den.aspects.fleet-cli.nixos =
    {
      config,
      pkgs,
      ...
    }:
    let
      controllerAddress = config.modules.fleet-update.controllerHost;
      controllerNames = lib.attrNames (
        lib.filterAttrs (_: address: address == controllerAddress) sshAddresses
      );
      controllerName =
        if builtins.length controllerNames == 1 then
          builtins.head controllerNames
        else
          throw "fleet-cli: fleet-update controllerHost must match exactly one den host";

      commandSpecs = {
        commands = {
          path = [ "commands" ];
          description = "List the generated fleet command surface";
          scope = "local";
          usage = "fleet commands [--json]";
          implementation = ''cmd_commands "$@"'';
        };
        health-probe = {
          path = [
            "health"
            "probe"
          ];
          description = "Run the existing fleet health probe on the controller";
          scope = "controller";
          usage = "fleet health probe [--strict] [--local]";
          implementation = ''cmd_health_probe "$@"'';
        };
        backup-status = {
          path = [
            "backup"
            "status"
          ];
          description = "Summarize offsite backup service and timer state across hosts";
          scope = "fleet";
          usage = "fleet backup status";
          implementation = ''cmd_backup_status "$@"'';
        };
        debug = {
          path = [ "debug" ];
          description = "Collect a concise diagnostic bundle locally or from a named host";
          scope = "host";
          usage = "fleet debug [host]";
          implementation = ''cmd_debug "$@"'';
        };
        update = {
          path = [ "update" ];
          description = "Run the shared host-update manual update path";
          scope = "host";
          usage = "fleet update [host-update arguments]";
          implementation = ''cmd_update "$@"'';
        };
      };

      specs = lib.mapAttrsToList (_: spec: spec) commandSpecs;
      sortedSpecs = lib.sort (a: b: builtins.length a.path > builtins.length b.path) specs;
      metadata = map (spec: {
        inherit (spec)
          path
          description
          scope
          usage
          ;
      }) specs;
      registry = pkgs.writeText "fleet-commands.json" (builtins.toJSON metadata);

      rootHelp = ''
        Usage: fleet <command> [arguments]

        Generated commands:
        ${lib.concatMapStringsSep "\n" (spec: "  ${spec.usage}\n      ${spec.description}") specs}

        Machine-readable discovery:
          fleet commands --json
      '';

      groups = lib.unique (
        map (spec: builtins.head spec.path) (lib.filter (spec: builtins.length spec.path > 1) specs)
      );

      groupDispatch = lib.concatMapStringsSep "\n" (
        group:
        let
          children = lib.filter (spec: builtins.head spec.path == group) specs;
          help = ''
            Usage: fleet ${group} <command> [arguments]

            Commands:
            ${lib.concatMapStringsSep "\n" (spec: "  ${spec.usage}\n      ${spec.description}") children}
          '';
        in
        ''
          if [ "''${1-}" = ${lib.escapeShellArg group} ] \
            && { [ "$#" -eq 1 ] || [ "''${2-}" = --help ] || [ "''${2-}" = -h ]; }; then
            printf '%s\n' ${lib.escapeShellArg help}
            exit 0
          fi
        ''
      ) groups;

      commandDispatch = lib.concatMapStringsSep "\n" (
        spec:
        let
          argc = builtins.length spec.path;
          conditions = lib.concatStringsSep " && " (
            lib.imap0 (i: part: ''[ "''${${toString (i + 1)}-}" = ${lib.escapeShellArg part} ]'') spec.path
          );
          shifts = lib.concatStringsSep "\n" (lib.genList (_: "shift") argc);
          help = ''
            Usage: ${spec.usage}

            ${spec.description}
            Scope: ${spec.scope}
          '';
        in
        ''
          if [ "$#" -ge ${toString argc} ] && ${conditions}; then
            ${shifts}
            if [ "''${1-}" = --help ] || [ "''${1-}" = -h ]; then
              printf '%s\n' ${lib.escapeShellArg help}
              exit 0
            fi
            ${spec.implementation}
            exit $?
          fi
        ''
      ) sortedSpecs;

      hostAddressCases = lib.concatMapStringsSep "\n" (host: ''
        ${lib.escapeShellArg host}) printf '%s\n' ${lib.escapeShellArg sshAddresses.${host}} ;;
      '') hostNames;
      hostWords = lib.concatMapStringsSep " " lib.escapeShellArg hostNames;

      fleet = pkgs.writeShellApplication {
        name = "fleet";
        runtimeInputs = with pkgs; [
          coreutils
          gawk
          jq
          openssh
          systemd
          util-linux
        ];
        text = ''
          registry=${lib.escapeShellArg registry}
          controller_name=${lib.escapeShellArg controllerName}
          controller_address=${lib.escapeShellArg controllerAddress}

          root_help() {
            printf '%s\n' ${lib.escapeShellArg rootHelp}
          }

          usage_error() {
            local key usage
            key="$*"
            usage=$(jq -r --arg key "$key" '.[] | select((.path | join(" ")) == $key) | .usage' "$registry")
            if [ -z "$usage" ] || [ "$usage" = null ]; then
              echo "unknown fleet command for usage: $key" >&2
              return 2
            fi
            printf 'usage: %s\n' "$usage" >&2
            return 2
          }

          host_address() {
            case "$1" in
          ${hostAddressCases}
              *) return 1 ;;
            esac
          }

          ssh_host() {
            local host="$1"
            shift
            local address
            address=$(host_address "$host") || {
              echo "unknown fleet host: $host" >&2
              return 2
            }
            ssh \
              -o BatchMode=yes \
              -o StrictHostKeyChecking=accept-new \
              -o ConnectTimeout=10 \
              "root@$address" "$@"
          }

          backup_status_local() {
            local host load active sub result exit_status last_exit timer_load timer_active last_trigger next last_success
            host="''${1:-$(hostname)}"
            load=$(systemctl show restic-backups-offsite.service -p LoadState --value 2>/dev/null || true)
            if [ "$load" != loaded ]; then
              printf '%s\tbackup=not-configured\n' "$host"
              return 0
            fi

            active=$(systemctl show restic-backups-offsite.service -p ActiveState --value 2>/dev/null || true)
            sub=$(systemctl show restic-backups-offsite.service -p SubState --value 2>/dev/null || true)
            result=$(systemctl show restic-backups-offsite.service -p Result --value 2>/dev/null || true)
            exit_status=$(systemctl show restic-backups-offsite.service -p ExecMainStatus --value 2>/dev/null || true)
            last_exit=$(systemctl show restic-backups-offsite.service -p ExecMainExitTimestamp --value 2>/dev/null || true)
            timer_load=$(systemctl show restic-backups-offsite.timer -p LoadState --value 2>/dev/null || true)
            timer_active=$(systemctl show restic-backups-offsite.timer -p ActiveState --value 2>/dev/null || true)
            last_trigger=$(systemctl show restic-backups-offsite.timer -p LastTriggerUSec --value 2>/dev/null || true)
            next=$(systemctl show restic-backups-offsite.timer -p NextElapseUSecRealtime --value 2>/dev/null || true)

            [ -n "$active" ] || active=unknown
            [ -n "$sub" ] || sub=unknown
            [ -n "$result" ] || result=unknown
            [ -n "$exit_status" ] || exit_status=unknown
            [ -n "$last_trigger" ] || last_trigger=unknown
            [ -n "$next" ] || next=unknown
            if [ "$result" = success ] && [ -n "$last_exit" ]; then
              last_success="$last_exit"
            else
              last_success=unknown
            fi
            if [ "$timer_load" != loaded ]; then
              timer_active=not-configured
              last_trigger=unknown
              next=unknown
            fi

            printf '%s\tservice=%s/%s result=%s exit=%s last_success=%s timer=%s last_trigger=%s next=%s\n' \
              "$host" "$active" "$sub" "$result" "$exit_status" "$last_success" \
              "$timer_active" "$last_trigger" "$next"

            if [ "$active" = failed ] || [ "$result" != success ] || { [ "$exit_status" != 0 ] && [ "$exit_status" != unknown ]; }; then
              return 1
            fi
            return 0
          }

          debug_local() {
            local host system_state current booted profile failed unit
            host=$(hostname)
            echo "== fleet debug: $host =="
            printf 'configuration_revision: '
            nixos-version --configuration-revision 2>/dev/null || echo unknown
            current=$(readlink -f /run/current-system 2>/dev/null || true)
            booted=$(readlink -f /run/booted-system 2>/dev/null || true)
            profile=$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)
            printf 'current_system: %s\n' "''${current:-unknown}"
            printf 'booted_system: %s\n' "''${booted:-unknown}"
            printf 'profile_system: %s\n' "''${profile:-unknown}"
            system_state=$(systemctl is-system-running 2>/dev/null || true)
            printf 'system_state: %s\n' "''${system_state:-unknown}"

            echo
            echo '== failed units =='
            failed=$(systemctl --failed --no-legend --plain 2>/dev/null || true)
            if [ -n "$failed" ]; then
              printf '%s\n' "$failed"
            else
              echo none
            fi

            echo
            echo '== filesystems =='
            df -h -x tmpfs -x devtmpfs 2>&1 || true

            if [ -n "$failed" ]; then
              echo
              echo '== failed-unit journal tails =='
              printf '%s\n' "$failed" | awk '{print $1}' | while IFS= read -r unit; do
                [ -n "$unit" ] || continue
                echo "--- $unit ---"
                journalctl -u "$unit" -n 20 --no-pager 2>&1 || true
              done
            fi

            echo
            echo '== update state =='
            if [ -r /var/lib/auto-update ] && [ -x /var/lib/auto-update ]; then
              if [ -e /var/lib/auto-update/PAUSE ]; then
                echo 'automation: PAUSED'
              else
                echo 'automation: active'
              fi
              for state_file in candidate target-revision deployed-revision rollback-streak; do
                if [ -r "/var/lib/auto-update/$state_file" ]; then
                  printf '%s: ' "$state_file"
                  cat "/var/lib/auto-update/$state_file"
                fi
              done
              for diff_file in /var/lib/auto-update/diff-*.txt; do
                [ -r "$diff_file" ] || continue
                echo "--- $diff_file (tail) ---"
                tail -n 40 "$diff_file"
              done
            elif [ -d /var/lib/auto-update ]; then
              echo 'controller state: present but unreadable (run as root for details)'
            else
              echo 'controller state: not present'
            fi
            if [ -r /tmp/host-update-diff.txt ]; then
              echo '--- /tmp/host-update-diff.txt (tail) ---'
              tail -n 40 /tmp/host-update-diff.txt
            fi
          }

          cmd_commands() {
            case "''${1-}" in
              "")
                jq -r '.[] | "\(.usage)\t\(.description)"' "$registry"
                ;;
              --json)
                cat "$registry"
                ;;
              *)
                usage_error commands
                ;;
            esac
          }

          cmd_health_probe() {
            if [ "$(hostname)" = "$controller_name" ]; then
              exec fleet-health-probe "$@"
            fi
            exec ssh \
              -o BatchMode=yes \
              -o StrictHostKeyChecking=accept-new \
              -o ConnectTimeout=10 \
              "root@$controller_address" fleet-health-probe "$@"
          }

          cmd_backup_status() {
            [ "$#" -eq 0 ] || {
              usage_error backup status
              return $?
            }
            local local_host host output host_rc rc
            rc=0
            local_host=$(hostname)
            for host in ${hostWords}; do
              if [ "$host" = "$local_host" ]; then
                host_rc=0
                backup_status_local "$host" || host_rc=$?
                [ "$host_rc" -eq 0 ] || rc=1
                continue
              fi

              host_rc=0
              output=$(ssh_host "$host" fleet __backup-status-local "$host" 2>&1) || host_rc=$?
              if [ "$host_rc" -eq 0 ]; then
                printf '%s\n' "$output"
              elif [ "$host_rc" -eq 255 ]; then
                printf '%s\tstatus=unreachable detail=%s\n' "$host" "$(printf '%s' "$output" | tail -n 1)"
                rc=1
              else
                printf '%s\n' "$output"
                rc=1
              fi
            done
            return "$rc"
          }

          cmd_debug() {
            [ "$#" -le 1 ] || {
              usage_error debug
              return $?
            }
            local target local_host
            local_host=$(hostname)
            target="''${1:-$local_host}"
            if ! host_address "$target" >/dev/null; then
              echo "unknown fleet host: $target" >&2
              return 2
            fi
            if [ "$target" = "$local_host" ]; then
              debug_local
            else
              ssh_host "$target" fleet __debug-local
            fi
          }

          cmd_update() {
            if ! command -v host-update >/dev/null 2>&1; then
              echo 'host-update is not in PATH; run fleet update as the configured operator user' >&2
              return 127
            fi
            exec host-update "$@"
          }

          # Internal entry points keep local and SSH execution on the same
          # implementation without exposing these helpers through discovery.
          case "''${1-}" in
            __backup-status-local)
              shift
              backup_status_local "$@"
              exit $?
              ;;
            __debug-local)
              shift
              [ "$#" -eq 0 ] || exit 2
              debug_local
              exit $?
              ;;
          esac

          if [ "$#" -eq 0 ] || [ "''${1-}" = --help ] || [ "''${1-}" = -h ]; then
            root_help
            exit 0
          fi

          ${groupDispatch}
          ${commandDispatch}

          echo "unknown fleet command: $*" >&2
          root_help >&2
          exit 2
        '';
      };
    in
    {
      options.modules.fleet-cli.package = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "Generated fleet operations CLI";
      };

      config = {
        modules.fleet-cli.package = fleet;
        environment.systemPackages = [ fleet ];
      };
    };
}
