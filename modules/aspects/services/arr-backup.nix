{ lib, ... }:
{
  den.aspects.nixos-services.provides.arr.nixos =
    { config, pkgs, ... }:
    let
      python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
      applications = {
        sonarr = {
          kind = "servarr";
          apiVersion = "v3";
          configFile = "/config/config.xml";
          backupDir = "/config/Backups/manual";
          managedDir = "/config/Backups/fleet";
        };
        radarr = {
          kind = "servarr";
          apiVersion = "v3";
          configFile = "/config/config.xml";
          backupDir = "/config/Backups/manual";
          managedDir = "/config/Backups/fleet";
        };
        prowlarr = {
          kind = "servarr";
          apiVersion = "v1";
          configFile = "/var/lib/prowlarr/config.xml";
          backupDir = "/var/lib/prowlarr/Backups/manual";
          managedDir = "/var/lib/prowlarr/Backups/fleet";
        };
        bazarr = {
          kind = "bazarr";
          configFile = "/config/config/config.yaml";
          backupDir = "/config/backup";
          managedDir = "/config/backup/fleet";
        };
      };
      producer =
        name: application:
        pkgs.writeShellApplication {
          name = "${name}-native-backup";
          runtimeInputs = [ python ];
          text = ''
            exec python3 ${../../scripts/native-arr-backup.py} ${
              pkgs.writeText "${name}-native-backup.json" (
                builtins.toJSON (
                  application
                  // {
                    app = name;
                    url = "http://127.0.0.1:${toString config.modules.services.definitions.${name}.port}";
                    pattern = "${name}_backup_*.zip";
                  }
                )
              )
            }
          '';
        };
    in
    {
      modules.backup.exports = lib.mapAttrs (name: _: {
        unit = "${name}-backup.service";
        machine = name;
        path = config.modules.services.definitions.${name}.backup.path;
        pattern = "${name}_backup_*.zip";
      }) applications;
      containers = lib.mapAttrs (name: application: {
        config.systemd.services."${name}-backup" = {
          description = "Create and verify native ${name} backup";
          serviceConfig = {
            Type = "oneshot";
            User = "root";
            TimeoutStartSec = "12min";
            PrivateTmp = true;
            ExecStart = lib.getExe (producer name application);
          };
        };
      }) applications;
    };

  perSystem = { pkgs, ... }: {
    checks.native-arr-backup =
      pkgs.runCommand "native-arr-backup"
        {
          nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
        }
        ''
          PYTHONDONTWRITEBYTECODE=1 python3 ${../../_tests/native-arr-backup.py} ${../../scripts/native-arr-backup.py}
          touch "$out"
        '';
  };
}
