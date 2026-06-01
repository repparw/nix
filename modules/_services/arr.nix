{ cfg, pkgs, ... }:
let
  mkArrContainer =
    {
      ipOctet,
      serviceConfig,
      extraBindMounts ? { },
      extraOptions ? { },
      extraConfig ? { },
    }:
    {
      autoStart = true;
      privateNetwork = true;
      privateUsers = "pick";
      hostAddress = "10.231.136.1";
      localAddress = "10.231.136.${toString ipOctet}";
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
        }
        // extraConfig;
    }
    // extraOptions;
in
{
  containers.bazarr = mkArrContainer {
    ipOctet = 2;
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
    ipOctet = 3;
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
    ipOctet = 4;
    serviceConfig.qbittorrent = {
      enable = true;
      openFirewall = true;
      torrentingPort = 54535;
    };
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
    serviceConfig.radarr = {
      enable = true;
      openFirewall = true;
    };
    extraConfig.environment.systemPackages = [ pkgs.striptracks ];
    extraBindMounts = {
      "/var/lib/radarr" = {
        hostPath = "${cfg.configDir}/radarr";
        isReadOnly = false;
      };
    };
  };

  containers.sonarr = mkArrContainer {
    ipOctet = 6;
    serviceConfig.sonarr = {
      enable = true;
      openFirewall = true;
    };
    extraConfig.environment.systemPackages = [ pkgs.striptracks ];
    extraBindMounts = {
      "/var/lib/sonarr" = {
        hostPath = "${cfg.configDir}/sonarr";
        isReadOnly = false;
      };
    };
  };
}
