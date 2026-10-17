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
        prepare = pkgs.writeShellApplication {
          name = "pi-services-backup";
          runtimeInputs = [
            pkgs.python3
            pkgs.sqlite
          ];
          text = ''
            exec python3 ${../scripts/pi-services-export.py} \
              ${lib.escapeShellArg source} ${state} 0 0
          '';
        };
      in
      {
        systemd.services.pi-services-backup = {
          description = "Prepare consistent Pi service exports for offsite backup";
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "pi-services-backup";
            StateDirectoryMode = "0700";
            UMask = "0077";
            ExecStart = lib.getExe prepare;
          };
        };
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
