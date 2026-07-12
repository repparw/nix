{
  lib,
  pkgs,
}:
let
  serviceDefinitions =
    cfg:
    let
      overlap = lib.intersectAttrs cfg.inventory cfg.definitions;
    in
    if overlap == { } then
      cfg.inventory // cfg.definitions
    else
      throw "services declared in both inventory and definitions: ${lib.concatStringsSep ", " (lib.attrNames overlap)}";

  serviceUrl =
    cfg: name:
    let
      service = (serviceDefinitions cfg).${name};
      address = if service.containerAddress != null then service.containerAddress else "127.0.0.1";
    in
    "http://${address}:${toString service.port}";

  backupServices = cfg: lib.filterAttrs (_: service: service.backup != null) (serviceDefinitions cfg);

  backupMountUnit = name: "home-containers-backup-${name}.mount";
in
{
  inherit serviceDefinitions serviceUrl backupMountUnit;

  inventoryHosts =
    cfg:
    lib.mapAttrsToList (_: service: "${service.hostname}.${cfg.domain}") (
      lib.filterAttrs (_: service: service.hostname != null) (serviceDefinitions cfg)
    );

  monitorSites =
    cfg:
    lib.mapAttrsToList
      (name: service: {
        title = name;
        url = "https://${service.hostname}.${cfg.domain}";
        check-url = serviceUrl cfg name;
      })
      (
        lib.filterAttrs (_: service: service.monitor && service.hostname != null && service.port != null) (
          serviceDefinitions cfg
        )
      );

  backupMounts =
    cfg:
    lib.mapAttrs' (
      name: service:
      lib.nameValuePair "${cfg.backupDir}/${name}" {
        depends = [ "/" ];
        device = service.backup.path;
        fsType = "none";
        options = [
          "bind"
          "ro"
          "nofail"
        ];
      }
    ) (backupServices cfg);

  containerBackupAfters =
    cfg:
    lib.mapAttrs' (
      name: _:
      lib.nameValuePair "container@${name}" {
        after = [ (backupMountUnit name) ];
      }
    ) (lib.filterAttrs (_: service: service.containerAddress != null) (backupServices cfg));

  backupAfter = names: map backupMountUnit names;

  mkContainer =
    {
      cfg,
      name,
      privateUsers ? null,
      bindMounts ? { },
      allowedDevices ? [ ],
      extraFlags ? [ ],
      forwardPorts ? [ ],
      serviceConfig ? { },
      extraConfig ? { },
      extraOptions ? { },
    }:
    {
      autoStart = true;
      privateNetwork = true;
      hostAddress = "10.231.136.1";
      localAddress = (serviceDefinitions cfg).${name}.containerAddress;
      inherit extraFlags;
      config =
        { ... }:
        lib.mkMerge [
          {
            services = serviceConfig;
            networking.useHostResolvConf = false;
            networking.nameservers = [ "10.231.136.1" ];
            system.stateVersion = "26.05";
          }
          extraConfig
        ];
    }
    // lib.optionalAttrs (privateUsers != null) { inherit privateUsers; }
    // lib.optionalAttrs (bindMounts != { }) { inherit bindMounts; }
    // lib.optionalAttrs (allowedDevices != [ ]) { inherit allowedDevices; }
    // lib.optionalAttrs (forwardPorts != [ ]) { inherit forwardPorts; }
    // extraOptions;

  mkBackupJob =
    {
      name,
      description,
      backupDir,
      filePattern,
      createBackup,
      owner ? null,
      group ? owner,
      retention ? 7,
      onCalendar ? "daily",
      randomizedDelaySec ? "30min",
      serviceConfig ? { },
    }:
    let
      pruneBackups = pkgs.writeShellApplication {
        name = "${name}-prune-backups";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
        ];
        text = ''
          set -euo pipefail
          cd "${backupDir}"
          find . -maxdepth 1 -type f -name '${filePattern}' -printf '%T@ %p\0' \
            | sort -z -rn \
            | tail -z -n +${toString (retention + 1)} \
            | cut -z -d ' ' -f 2- \
            | xargs -0 -r rm -v
        '';
      };

      installBackupDir = lib.optionalAttrs (owner != null) {
        ExecStartPre = "+${lib.getExe' pkgs.coreutils "install"} -d -m 0750 -o ${owner} -g ${group} ${backupDir}";
      };
    in
    {
      systemd.services."${name}-backup" = {
        description = "Create ${description} backup";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe createBackup;
          ExecStartPost = lib.getExe pruneBackups;
        }
        // installBackupDir
        // serviceConfig;
        wantedBy = [ ];
      };

      systemd.timers."${name}-backup" = {
        description = "Run ${description} backup";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = onCalendar;
          Persistent = true;
          RandomizedDelaySec = randomizedDelaySec;
        };
      };
    };
}
