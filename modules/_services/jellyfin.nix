{
  cfg,
  lib,
  pkgs,
  ...
}:
{
  containers.jellyfin = {
    autoStart = true;
    privateNetwork = true;
    privateUsers = "pick";
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.10";
    bindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/jellyfin";
        isReadOnly = false;
      };
      "/data/media" = {
        hostPath = "${cfg.dataDir}/media";
        isReadOnly = false;
      };
      "/data/seagate" = {
        hostPath = cfg.externalDataDir;
        isReadOnly = false;
      };
    };
    allowedDevices = [
      {
        node = "/dev/dri/renderD128";
        modifier = "rwm";
      }
      {
        node = "/dev/dri/card0";
        modifier = "rwm";
      }
    ];
    config =
      { ... }:
      {
        services.jellyfin = {
          enable = true;
          openFirewall = true;
        };

        hardware.graphics = {
          enable = true;
          extraPackages = with pkgs; [
            libva-vdpau-driver
            libvdpau-va-gl
            mesa.drivers
          ];
        };

        users.users.jellyfin.extraGroups = [
          "video"
          "render"
        ];

        system.stateVersion = "26.05";
      };
  };
}
