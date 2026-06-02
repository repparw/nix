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
      hostAddress = "10.231.136.1";
      localAddress = "10.231.136.${toString ipOctet}";
      inherit extraFlags;
      bindMounts = extraBindMounts;
      config =
        { ... }:
        {
          services = serviceConfig;
          system.stateVersion = "26.05";
          networking.useHostResolvConf = false;
          networking.nameservers = [ "10.231.136.1" ];
        }
        // extraConfig;
    }
    // extraOptions;
in
{
  containers.bazarr = mkArrContainer {
    ipOctet = 2;
    extraOptions.privateUsers = "identity";
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
    extraOptions.privateUsers = "identity";
    serviceConfig.prowlarr = {
      enable = true;
      openFirewall = true;
    };
    extraBindMounts = {
      "/var/lib/private/prowlarr/Backups" = {
        hostPath = "${cfg.configDir}/prowlarr/Backups";
        isReadOnly = false;
      };
    };
  };

  containers.qbittorrent = mkArrContainer {
    ipOctet = 4;
    extraOptions.privateUsers = "identity";
    serviceConfig.qbittorrent = {
      enable = true;
      openFirewall = true;
      torrentingPort = 54535;
      profileDir = "/var/lib/qbittorrent";
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
      "/var/lib/qbittorrent/qBittorrent" = {
        hostPath = "${cfg.configDir}/qbittorrent";
        isReadOnly = false;
      };
      "/downloading" = {
        hostPath = "${cfg.configDir}/downloading";
        isReadOnly = false;
      };
    };
  };

  containers.radarr = mkArrContainer {
    ipOctet = 5;
    extraOptions.privateUsers = "identity";
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
    extraOptions.privateUsers = "identity";
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
}
