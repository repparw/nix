{ cfg, lib, ... }:
let
  mkArrContainer =
    {
      port,
      serviceConfig,
      extraBindMounts ? { },
    }:
    {
      autoStart = true;
      privateNetwork = true;
      privateUsers = "pick";
      hostAddress = "10.231.136.1";
      localAddress = "10.231.136.${toString port}";
      bindMounts = {
        "/data" = {
          hostPath = cfg.dataDir;
          isReadOnly = false;
        };
        "/data/seagate" = {
          hostPath = cfg.externalDataDir;
          isReadOnly = false;
        };
      }
      // extraBindMounts;
      config =
        { ... }:
        {
          services = serviceConfig;
          system.stateVersion = "26.05";
        };
    };
in
{
  containers.bazarr = mkArrContainer {
    port = 2;
    serviceConfig.bazarr = {
      enable = true;
      openFirewall = true;
    };
    extraBindMounts = {
      "/var/lib/bazarr" = {
        hostPath = "${cfg.configDir}/bazarr";
        isReadOnly = false;
      };
    };
  };

  containers.prowlarr = mkArrContainer {
    port = 3;
    serviceConfig.prowlarr = {
      enable = true;
      openFirewall = true;
    };
    extraBindMounts = {
      "/var/lib/prowlarr" = {
        hostPath = "${cfg.configDir}/prowlarr";
        isReadOnly = false;
      };
    };
  };

  containers.qbittorrent = mkArrContainer {
    port = 4;
    serviceConfig.qbittorrent = {
      enable = true;
      openFirewall = true;
      torrentingPort = 54535;
    };
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
    port = 5;
    serviceConfig.radarr = {
      enable = true;
      openFirewall = true;
    };
    extraBindMounts = {
      "/var/lib/radarr" = {
        hostPath = "${cfg.configDir}/radarr";
        isReadOnly = false;
      };
    };
  };

  containers.sonarr = mkArrContainer {
    port = 6;
    serviceConfig.sonarr = {
      enable = true;
      openFirewall = true;
    };
    extraBindMounts = {
      "/var/lib/sonarr" = {
        hostPath = "${cfg.configDir}/sonarr";
        isReadOnly = false;
      };
    };
  };
}
