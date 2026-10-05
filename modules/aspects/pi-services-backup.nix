{ den, ... }:
{
  den.aspects.pi-services-backup = {
    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        source = "${config.users.users.repparw.home}/services";
        state = "/var/lib/pi-services-backup";
        sender = pkgs.writeShellApplication {
          name = "pi-services-backup-send";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.util-linux
            pkgs.rsync
            pkgs.python3
            pkgs.sqlite
          ];
          text = ''
            # Accept only the sender contract emitted by the fleet's rsync job.
            [ "$#" = 5 ] && [ "$1" = --server ] && [ "$2" = --sender ] \
              && [ "$4" = . ] && [ "$5" = ${lib.escapeShellArg "${state}/current/"} ] \
              || { echo "unsupported Pi backup sender command" >&2; exit 2; }
            case "$3" in
              -lLogDtpre.LsfxCIvu|-nlLogDtpre.LsfxCIvu) ;;
              *) echo "unsupported Pi backup sender flags" >&2; exit 2 ;;
            esac
            [ "$(id -u)" = 0 ] || { echo "Pi backup preparation requires root" >&2; exit 1; }
            umask 077
            exec 9>/run/pi-services-backup.lock
            flock -w 1200 9
            install -d -m 0711 -o root -g root ${state}
            backup_uid=$(id -u repparw)
            backup_gid=$(id -g repparw)
            python3 ${../scripts/pi-services-export.py} \
              ${lib.escapeShellArg source} ${state} "$backup_uid" "$backup_gid"
            # The inherited lock keeps this generation stable until rsync exits.
            exec setpriv --reuid="$backup_uid" --regid="$backup_gid" --clear-groups rsync "$@"
          '';
        };
      in
      {
        environment.systemPackages = [ sender ];
      };
  };
  perSystem = { pkgs, ... }: {
    checks.pi-services-export =
      pkgs.runCommand "pi-services-export"
        {
          nativeBuildInputs = [
            pkgs.python3
            pkgs.rsync
            pkgs.sqlite
          ];
        }
        ''
          PYTHONDONTWRITEBYTECODE=1 python3 ${../scripts/pi-services-export.test.py} ${../scripts/pi-services-export.py}
          touch "$out"
        '';
  };
}
