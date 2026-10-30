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
      # Container units on epsilon, derived from the fleet service registry
      # (host == epsilon with container = true) instead of a hardcoded list,
      # so the reboot gate cannot drift when services move between hosts.
      epsilonContainers = lib.concatStringsSep " " (
        map (name: "container@${name}") (
          lib.attrNames (
            lib.filterAttrs (_: service: service.host == "epsilon" && service.container) (
              config.modules.services.definitions or { }
            )
          )
        )
      );

      servicesLib = import ../_services/lib.nix { inherit lib pkgs; };
      cfg = config.modules.services;
      apexUrl = "https://${cfg.domain}/";
      minifluxHealth = servicesLib.publicHealthUrl cfg config "miniflux";
      packageDelivery = pkgs.writeShellApplication {
        name = "fleet-package-deliver";
        runtimeInputs = with pkgs; [
          coreutils
          jq
          openssh
          util-linux
        ];
        text =
          builtins.replaceStrings
            [ "@FLEET_EPSILON_ADDRESS@" ]
            [ config.modules.fleet-update.targetAddresses.epsilon ]
            (builtins.readFile ../scripts/package-update-deliver.sh);
      };
      headlessReboot = pkgs.writeShellApplication {
        name = "fleet-headless-reboot";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          openssh
          systemd
          util-linux
          config.modules.fleet-reboot.predicate
          (servicesLib.mkDiscordNotify pkgs config.modules.services.discordChannelId)
        ];
        text =
          builtins.replaceStrings
            [
              "@FLEET_EPSILON_ADDRESS@"
              "@FLEET_EPSILON_CONTAINERS@"
              "@FLEET_APEX_URL@"
              "@FLEET_MINIFLUX_HEALTH@"
            ]
            [
              config.modules.fleet-update.targetAddresses.epsilon
              epsilonContainers
              apexUrl
              minifluxHealth
            ]
            (builtins.readFile ../scripts/fleet-headless-reboot.sh);
      };
    in
    {
      environment.systemPackages = [ config.modules.fleet-update.package ];
      systemd.tmpfiles.rules = [ "d /var/lib/auto-update 0700 root root -" ];

      systemd.services.fleet-headless-reboot = {
        description = "Sequentially reboot headless hosts into staged kernel/initrd generations";
        # Ordering after the transient deploy unit makes a post-deploy
        # trigger wait for the deployment to finish (and release the fleet
        # lock) before the sequence starts; the timer is unaffected when no
        # deploy is running.
        after = [
          "network-online.target"
          "fleet-deploy-run.service"
        ];
        wants = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          TimeoutStartSec = "30min";
          ExecStart = lib.getExe headlessReboot;
        };
      };

      # Safety net for the post-deploy trigger: catches whatever a deploy
      # deferred (busy backup) or skipped (manual rebuild without a deploy).
      systemd.timers.fleet-headless-reboot = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 03:00:00";
          Persistent = false;
        };
      };

      systemd.services.fleet-deploy = {
        description = "Launch convergence on main after successful CI";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig.Type = "oneshot";
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

      systemd.services.fleet-package-deliver = {
        description = "Deliver durable fleet package events to Hermes";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "auto-update";
          TimeoutStartSec = "5min";
          ExecStart = lib.getExe packageDelivery;
        };
      };
      systemd.timers.fleet-package-deliver = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitInactiveSec = "5min";
        };
      };

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
