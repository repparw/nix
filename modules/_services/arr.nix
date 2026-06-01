{
  cfg,
  lib,
  pkgs,
  ...
}:
let
  mkArrContainer =
    {
      ipOctet,
      serviceConfig,
      extraBindMounts ? { },
      extraOptions ? { },
      extraConfig ? { },
      extraFlags ? [
        "--bind=${cfg.dataDir}:/data"
        "--bind=${cfg.externalDataDir}:/seagate"
      ],
    }:
    {
      autoStart = true;
      privateNetwork = true;
      privateUsers = "pick";
      hostAddress = "10.231.136.1";
      localAddress = "10.231.136.${toString ipOctet}";
      inherit extraFlags;
      bindMounts = extraBindMounts;
      config =
        { ... }:
        {
          services = serviceConfig;
          system.stateVersion = "26.05";
        }
        // extraConfig;
    }
    // extraOptions;
in
{
  containers.bazarr = mkArrContainer {
    ipOctet = 2;
    extraOptions.privateUsers = 30000;
    serviceConfig.bazarr = {
      enable = true;
      openFirewall = true;
      dataDir = "/config";
    };
    extraConfig.systemd.tmpfiles.rules = [ ];
    extraBindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/bazarr";
        isReadOnly = false;
      };
    };
  };

  containers.prowlarr = mkArrContainer {
    ipOctet = 3;
    extraOptions.privateUsers = 31000;
    serviceConfig.prowlarr = {
      enable = true;
      openFirewall = true;
      settings.server.bindAddress = "*";
      dataDir = "/config";
    };
    extraConfig = {
      systemd.services.prowlarr.serviceConfig = {
        DynamicUser = lib.mkForce false;
        StateDirectory = lib.mkForce "";
        User = "prowlarr";
      };
      users.users.prowlarr = {
        isSystemUser = true;
        group = "prowlarr";
      };
      users.groups.prowlarr = { };
      systemd.tmpfiles.rules = [ ];
    };
    extraBindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/prowlarr";
        isReadOnly = false;
      };
    };
  };

  containers.qbittorrent = mkArrContainer {
    ipOctet = 4;
    serviceConfig.qbittorrent = {
      enable = true;
      openFirewall = true;
      torrentingPort = 54535;
    };
    extraFlags = [ "--bind=${cfg.dataDir}:/data" ];
    extraOptions.forwardPorts = [
      {
        protocol = "tcp";
        hostPort = 54535;
        containerPort = 54535;
      }
      {
        protocol = "udp";
        hostPort = 54535;
        containerPort = 54535;
      }
    ];
    extraBindMounts = {
      "/var/lib/qbittorrent" = {
        hostPath = "${cfg.configDir}/qbittorrent";
        isReadOnly = false;
      };
      "/var/lib/qbittorrent/downloading" = {
        hostPath = "${cfg.configDir}/downloading";
        isReadOnly = false;
      };
    };
  };

  containers.radarr = mkArrContainer {
    ipOctet = 5;
    extraOptions.privateUsers = 32000;
    serviceConfig.radarr = {
      enable = true;
      openFirewall = true;
      settings.server.bindAddress = "*";
      dataDir = "/config";
    };
    extraConfig = {
      environment.systemPackages = [ pkgs.striptracks ];
      systemd.tmpfiles.rules = [ ];
    };
    extraBindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/radarr";
        isReadOnly = false;
      };
    };
  };

  containers.sonarr = mkArrContainer {
    ipOctet = 6;
    extraOptions.privateUsers = 33000;
    serviceConfig.sonarr = {
      enable = true;
      openFirewall = true;
      settings.server.bindAddress = "*";
      dataDir = "/config";
    };
    extraConfig = {
      environment.systemPackages = [ pkgs.striptracks ];
      systemd.tmpfiles.rules = [ ];
    };
    extraBindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/sonarr";
        isReadOnly = false;
      };
    };
  };

  systemd.services = {
    "container@bazarr".preStart = "chown -R 30999:30999 ${cfg.configDir}/bazarr";
    "container@prowlarr".preStart = "chown -R 31997:31995 ${cfg.configDir}/prowlarr";
    "container@radarr".preStart = "chown -R 32275:32275 ${cfg.configDir}/radarr";
    "container@sonarr".preStart = "chown -R 33274:33274 ${cfg.configDir}/sonarr";
  };
}
