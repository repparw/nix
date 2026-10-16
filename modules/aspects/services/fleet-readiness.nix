{ den, ... }:
{
  den.aspects.nixos-services.provides.fleet-readiness = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
        probe = pkgs.writeShellApplication {
          name = "fleet-readiness-probe";
          runtimeInputs = with pkgs; [
            coreutils
            jq
            openssh
            util-linux
          ];
          text =
            builtins.replaceStrings
              [ "@FLEET_ALPHA_ADDRESS@" ]
              [ (lib.escapeShellArg config.modules.fleet-update.targetAddresses.alpha) ]
              (builtins.readFile ../../scripts/fleet-readiness-probe.sh);
        };
        deliver = pkgs.writeShellApplication {
          name = "fleet-readiness-deliver";
          runtimeInputs = with pkgs; [
            coreutils
            jq
            (servicesLib.mkDiscordNotify pkgs config.modules.services.discordChannelId)
            util-linux
          ];
          text = builtins.readFile ../../scripts/fleet-readiness-deliver.sh;
        };
      in
      {
        options.modules.fleet-readiness.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether this host runs the fleet readiness probe and deliverer.
            Only the deployment controller (Pi) needs it.
          '';
        };

        config = lib.mkIf config.modules.fleet-readiness.enable {
          systemd.services.fleet-readiness-probe = {
            description = "Probe Alpha runtime readiness for host-owned upstream waits";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            restartIfChanged = false;
            serviceConfig = {
              Type = "oneshot";
              StateDirectory = "auto-update";
              TimeoutStartSec = "5min";
              ExecStart = lib.getExe probe;
            };
          };
          systemd.timers.fleet-readiness-probe = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "10min";
              OnUnitInactiveSec = "2h";
            };
          };

          systemd.services.fleet-readiness-deliver = {
            description = "Deliver durable fleet readiness events to Discord";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              StateDirectory = "auto-update";
              TimeoutStartSec = "5min";
              ExecStart = lib.getExe deliver;
            };
          };
          systemd.timers.fleet-readiness-deliver = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "2min";
              OnUnitInactiveSec = "5min";
            };
          };
        };
      };
  };
}
