{ den, ... }:
{
  den.aspects.fleet-controller.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # One controller-side transaction owns both headless reboots. Holding
      # the normal fleet lock across epsilon's reboot and recovery prevents
      # promote/deploy from racing either host, while the post-boot health
      # gate prevents pi from going down unless epsilon is back.
      headlessReboot = pkgs.writeShellApplication {
        name = "fleet-headless-reboot";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          openssh
          systemd
          util-linux
        ];
        text = ''
          deploy_key="''${FLEET_DEPLOY_KEY:-/home/repparw/.ssh/id_ed25519}"
          if [ ! -r "$deploy_key" ]; then
            echo "deployment key is not readable: $deploy_key" >&2
            exit 1
          fi

          # Same lock as fleet-update. Keep fd 9 open for the entire
          # epsilon -> health gate -> pi transaction.
          exec 9>/run/fleet-update.lock
          if ! flock -n 9; then
            echo "fleet-headless-reboot: another fleet operation is running; skipping"
            exit 0
          fi

          epsilon=${lib.escapeShellArg config.modules.services.hostAddresses.epsilon}
          ssh_options=(
            -i "$deploy_key"
            -o BatchMode=yes
            -o IdentitiesOnly=yes
            -o StrictHostKeyChecking=accept-new
            -o ConnectTimeout=10
          )

          remote_epsilon() {
            # Arguments are intentionally expanded by this client-side wrapper.
            # shellcheck disable=SC2029
            ssh "''${ssh_options[@]}" "root@$epsilon" "$@"
          }

          reboot_required_local() {
            local booted built
            if ! booted=$(readlink /run/booted-system/{initrd,kernel,kernel-modules} 2>/dev/null); then
              return 2
            fi
            if ! built=$(readlink /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules} 2>/dev/null); then
              return 2
            fi
            [ "$booted" != "$built" ]
          }

          reboot_required_epsilon() {
            remote_epsilon bash -s <<'EOF'
          booted=$(readlink /run/booted-system/{initrd,kernel,kernel-modules} 2>/dev/null) || exit 2
          built=$(readlink /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules} 2>/dev/null) || exit 2
          [ "$booted" != "$built" ]
          EOF
          }

          http_200() {
            [ "$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$1" || true)" = 200 ]
          }

          epsilon_healthy() {
            local state
            state=$(remote_epsilon systemctl is-system-running 2>/dev/null || true)
            case "$state" in
              running | degraded) ;;
              *) return 1 ;;
            esac
            remote_epsilon systemctl is-active --quiet \
              container@hermes.service container@authelia.service \
              container@miniflux.service container@archisteamfarm.service traefik.service \
              || return 1
            http_200 https://repparw.com/ || return 1
            http_200 https://rss.repparw.com/healthcheck || return 1
          }

          backup_state_epsilon() {
            remote_epsilon systemctl is-active restic-backups-offsite.service 2>/dev/null || true
          }

          backup_state_local() {
            systemctl is-active restic-backups-offsite.service 2>/dev/null || true
          }

          backup_is_busy() {
            case "$1" in
              active | activating | reloading | deactivating) return 0 ;;
              inactive | failed) return 1 ;;
              *) return 2 ;;
            esac
          }

          wait_epsilon_reboot() {
            local old_boot_id="$1" boot_id passes=0
            local deadline=$((SECONDS + 1200))
            while [ "$SECONDS" -lt "$deadline" ]; do
              boot_id=$(remote_epsilon cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)
              if [ -n "$boot_id" ] && [ "$boot_id" != "$old_boot_id" ]; then
                if epsilon_healthy; then
                  passes=$((passes + 1))
                  if [ "$passes" -ge 2 ]; then
                    return 0
                  fi
                else
                  passes=0
                fi
              fi
              sleep 15
            done
            return 1
          }

          epsilon_pending=0
          if reboot_required_epsilon; then
            epsilon_pending=1
          else
            rc=$?
            if [ "$rc" -ne 1 ]; then
              echo "fleet-headless-reboot: cannot determine epsilon boot state; refusing sequence" >&2
              exit 1
            fi
          fi

          pi_pending=0
          if reboot_required_local; then
            pi_pending=1
          else
            rc=$?
            if [ "$rc" -ne 1 ]; then
              echo "fleet-headless-reboot: cannot determine pi boot state; refusing sequence" >&2
              exit 1
            fi
          fi

          if [ "$epsilon_pending" -eq 0 ] && [ "$pi_pending" -eq 0 ]; then
            echo "fleet-headless-reboot: both headless hosts already converged"
            exit 0
          fi

          if [ "$epsilon_pending" -eq 1 ]; then
            epsilon_backup=$(backup_state_epsilon)
            if backup_is_busy "$epsilon_backup"; then
              echo "fleet-headless-reboot: epsilon backup is $epsilon_backup; deferring sequence"
              exit 0
            else
              rc=$?
              if [ "$rc" -ne 1 ]; then
                echo "fleet-headless-reboot: cannot determine epsilon backup state; refusing sequence" >&2
                exit 1
              fi
            fi

            old_boot_id=$(remote_epsilon cat /proc/sys/kernel/random/boot_id 2>/dev/null) || {
              echo "fleet-headless-reboot: cannot read epsilon boot id; refusing reboot" >&2
              exit 1
            }
            echo "fleet-headless-reboot: rebooting epsilon into staged kernel/initrd"
            remote_epsilon systemctl reboot --no-block
            if ! wait_epsilon_reboot "$old_boot_id"; then
              echo "fleet-headless-reboot: epsilon did not return healthy after reboot; pi stays up" >&2
              exit 1
            fi
            if reboot_required_epsilon; then
              echo "fleet-headless-reboot: epsilon rebooted but is still on a mismatched kernel/initrd; pi stays up" >&2
              exit 1
            else
              rc=$?
              if [ "$rc" -ne 1 ]; then
                echo "fleet-headless-reboot: cannot verify epsilon convergence; pi stays up" >&2
                exit 1
              fi
            fi
          fi

          if [ "$pi_pending" -eq 0 ]; then
            echo "fleet-headless-reboot: pi already converged"
            exit 0
          fi

          # Even when epsilon itself did not need a reboot, pi only goes down
          # behind a live edge. Check immediately before requesting shutdown.
          if ! epsilon_healthy; then
            echo "fleet-headless-reboot: epsilon health gate is failing; pi stays up" >&2
            exit 1
          fi

          pi_backup=$(backup_state_local)
          if backup_is_busy "$pi_backup"; then
            echo "fleet-headless-reboot: pi backup is $pi_backup; deferring pi reboot"
            exit 0
          else
            rc=$?
            if [ "$rc" -ne 1 ]; then
              echo "fleet-headless-reboot: cannot determine pi backup state; refusing reboot" >&2
              exit 1
            fi
          fi

          echo "fleet-headless-reboot: rebooting pi into staged kernel/initrd"
          systemctl reboot --no-block

          # Hold the fleet lock until shutdown actually tears this service
          # down; otherwise a manual fleet run could enter after the reboot
          # request was queued but before pi leaves userspace.
          exec sleep infinity
        '';
      };
    in
    {
      # Install the controller only on the coordinator. Other nodes are
      # deploy-rs targets, not alternate fleet coordinators.
      environment.systemPackages = [ config.modules.fleet-update.package ];
      systemd.tmpfiles.rules = [ "d /var/lib/auto-update 0700 root root -" ];

      # Headless kernel/initrd convergence is one controller-owned
      # transaction. Persistent=false deliberately avoids a catch-up reboot
      # when pi boots after the 03:00 maintenance window.
      systemd.services.fleet-headless-reboot = {
        description = "Sequentially reboot headless hosts into staged kernel/initrd generations";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "30min";
          ExecStart = lib.getExe headlessReboot;
        };
      };

      systemd.timers.fleet-headless-reboot = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 03:00:00";
          Persistent = false;
        };
      };

      # Promotion and consumption are independent transactions. A failed
      # input bump cannot suppress deployment of already-approved main; the
      # shared controller lock serializes their Git and state access.
      systemd.services.fleet-promote = {
        description = "Validate and publish a flake.lock candidate";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          WorkingDirectory = "/var/lib/auto-update";
          StateDirectory = "auto-update";
          TimeoutStartSec = "120min";
        };
        script = ''
          exec ${lib.getExe config.modules.fleet-update.package} \
            promote --state /var/lib/auto-update
        '';
      };

      systemd.timers.fleet-promote = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 04:15:00";
          Persistent = true;
          RandomizedDelaySec = "10min";
        };
      };

      systemd.services.fleet-deploy = {
        description = "Launch convergence on the approved main revision";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig.Type = "oneshot";
        # Pi is itself a deployment target. Run the long-lived worker as a
        # transient unit outside the configuration it may replace.
        script = ''
          if ${lib.getExe' pkgs.systemd "systemctl"} is-active --quiet fleet-deploy-run.service; then
            echo "fleet-deploy-run.service is already active"
            exit 0
          fi
          if ${lib.getExe' pkgs.systemd "systemd-run"} \
            --unit=fleet-deploy-run \
            --collect \
            --no-block \
            --property=Type=exec \
            --property=RuntimeMaxSec=180min \
            --working-directory=/var/lib/auto-update \
            ${lib.getExe config.modules.fleet-update.package} \
              deploy --wait-lock 7200 --state /var/lib/auto-update; then
            exit 0
          fi
          # The activity check and unit creation cannot be one atomic call.
          # If another launcher won that race, convergence is already owned.
          if ${lib.getExe' pkgs.systemd "systemctl"} is-active --quiet fleet-deploy-run.service; then
            echo "fleet-deploy-run.service was started concurrently"
            exit 0
          fi
          exit 1
        '';
      };

      systemd.timers.fleet-deploy = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 05:30:00";
          Persistent = true;
          RandomizedDelaySec = "10min";
        };
      };

      # Keep retries on the controller. An alpha-local service would remain
      # active while replacing itself and can make systemd reject the
      # activation transaction as cyclic.
      systemd.services.fleet-alpha-retry = {
        description = "Retry gated alpha fleet convergence";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          WorkingDirectory = "/var/lib/auto-update";
          StateDirectory = "auto-update";
          TimeoutStartSec = "240min";
        };
        script = ''
          exec ${lib.getExe config.modules.fleet-update.package} \
            deploy --host alpha --wait-lock 10800 --state /var/lib/auto-update
        '';
      };

      systemd.timers.fleet-alpha-retry = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 07:00:00";
          Persistent = true;
          RandomizedDelaySec = "15min";
        };
      };
    };
}
