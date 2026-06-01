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
    extraFlags = [
      "--bind=${cfg.dataDir}/media:/data/media"
      "--bind=${cfg.externalDataDir}:/seagate"
    ];
    bindMounts = {
      "/config" = {
        hostPath = "${cfg.configDir}/jellyfin";
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
        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];

        services.jellyfin = {
          enable = true;
          openFirewall = true;
        };

        hardware.graphics = {
          enable = true;
          extraPackages = with pkgs; [
            libva-vdpau-driver
            libvdpau-va-gl
            intel-media-driver
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
