{ den, ... }:
{
  den.aspects.fleet-controller.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Install the controller only on the coordinator. Other nodes are
      # deploy-rs targets, not alternate fleet coordinators.
      environment.systemPackages = [ config.modules.fleet-update.package ];
      systemd.tmpfiles.rules = [ "d /var/lib/auto-update 0700 root root -" ];

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
