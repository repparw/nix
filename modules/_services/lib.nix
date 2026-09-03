{
  lib,
  pkgs,
}:
let
  serviceUrl =
    cfg: name:
    let
      service = cfg.definitions.${name};
      # Remote backends (host set) are reached via the hosting machine's LAN
      # address and published port; local backends keep host-local addressing
      # (container bridge or own loopback).
      target =
        if service.host != null then
          "${cfg.hostAddresses.${service.host}}:${
            toString (if service.publishedPort != null then service.publishedPort else service.port)
          }"
        else
          "${
            if service.containerAddress != null then service.containerAddress else "127.0.0.1"
          }:${toString service.port}";
    in
    "http://${target}";

  backupServices = cfg: lib.filterAttrs (_: service: service.backup != null) cfg.definitions;

  backupMountUnit = name: "home-containers-backup-${name}.mount";

  # Public healthcheck URL: "https://<host>.<domain><healthcheck>" for
  # services that expose one, else the internal backend URL.
  publicHealthUrl =
    cfg: name:
    let
      service = cfg.definitions.${name};
    in
    if service.healthcheck != null then
      "https://${service.hostname}.${cfg.domain}${service.healthcheck}"
    else
      serviceUrl cfg name;
in
{
  inherit serviceUrl publicHealthUrl;

  serviceHosts =
    cfg:
    lib.mapAttrsToList (_: service: "${service.hostname}.${cfg.domain}") (
      lib.filterAttrs (_: service: service.hostname != null) cfg.definitions
    );

  # Post-edge contract: probe the public endpoint itself so the widget
  # reflects what a visitor experiences — CF, terminating edge, tunnel, and
  # backend all included. Services exposing a healthcheck (authelia-bypassed)
  # are probed at https://host/healthcheck expecting a real 200; services
  # without one are probed at their internal backend, where a redirect to
  # their own login (jellyfin -> /web, paperless -> /login) still means "up".
  monitorSites =
    cfg:
    lib.mapAttrsToList
      (
        name: service:
        if service.healthcheck != null then
          {
            title = name;
            url = "https://${service.hostname}.${cfg.domain}";
            check-url = publicHealthUrl cfg name;
          }
        else
          {
            title = name;
            url = "https://${service.hostname}.${cfg.domain}";
            check-url = serviceUrl cfg name;
            alt-status-codes = [ 302 ];
          }
      )
      (
        lib.filterAttrs (
          _: service: service.monitor && service.hostname != null && service.port != null
        ) cfg.definitions
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
      # Bridge gateway for the container; container DNS points here. Hosts
      # overriding hostAddress (epsilon's 10.231.137.x) must override
      # extraConfig.networking.nameservers to match.
      hostAddress ? "10.231.136.1",
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
      hostAddress = lib.mkDefault hostAddress;
      localAddress = lib.mkDefault cfg.definitions.${name}.containerAddress;
      inherit extraFlags;
      config =
        { ... }:
        lib.mkMerge [
          {
            services = serviceConfig;
            networking.useHostResolvConf = false;
            networking.nameservers = lib.mkDefault [ hostAddress ];
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
