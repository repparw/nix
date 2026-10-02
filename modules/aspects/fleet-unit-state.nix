{ den, ... }:
{
  den.aspects.fleet-unit-state.nixos =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      stateDir = "/var/lib/fleet-unit-state";
      snapshot = pkgs.writeShellApplication {
        name = "fleet-unit-snapshot";
        runtimeInputs = with pkgs; [
          coreutils
          findutils
          gawk
          systemd
        ];
        text = builtins.readFile ./fleet-unit-state/snapshot.sh;
      };
      record = pkgs.writeShellApplication {
        name = "fleet-unit-record";
        runtimeInputs = [ pkgs.coreutils ];
        text = builtins.readFile ./fleet-unit-state/record.sh;
      };
      trackedJobs =
        config.modules.fleet-unit-state.retainedJobs
        ++ map (name: "rsync-job-${name}") (lib.attrNames config.services.rsync.jobs);
    in
    {
      options.modules.fleet-unit-state.retainedJobs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "restic-backups-offsite" ];
        description = "One-shot services whose failed result is retained until a successful rerun";
      };
      options.modules.fleet-unit-state.snapshot = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "Local failed units and retained scheduled job failures";
      };
      config = {
        modules.fleet-unit-state.snapshot = snapshot;
        environment.systemPackages = [ snapshot ];
        systemd.tmpfiles.rules = [ "d ${stateDir} 0700 root root -" ];
        systemd.services = lib.genAttrs trackedJobs (_: {
          serviceConfig = {
            ExecStopPost = [ "+${lib.getExe record} %n" ];
            ReadWritePaths = [ stateDir ];
          };
        });
      }
      // lib.optionalAttrs (options ? environment.persistence) {
        environment.persistence = {
          "/persist".directories = [
            {
              directory = stateDir;
              mode = "0700";
            }
          ];
        };
      };
    };
}
