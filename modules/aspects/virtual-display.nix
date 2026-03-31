{
  lib,
  ...
}:
{
  den.aspects.virtual-display = {
    nixos =
      { config, pkgs, ... }:
      {
        options.modules.virtualDisplay = {
          port = lib.mkOption {
            type = lib.types.str;
            default = "DP-2";
            description = "GPU port to use for virtual display";
          };
          resolution = lib.mkOption {
            type = lib.types.str;
            default = "2560x1440";
            description = "Resolution for virtual display";
          };
          refreshRate = lib.mkOption {
            type = lib.types.int;
            default = 120;
            description = "Refresh rate for virtual display";
          };
        };

        config = {
          hardware.firmware = [ pkgs.edid-generator ];
          boot.kernelParams = [
            "drm.edid_firmware=${config.modules.virtualDisplay.port}:edid/${config.modules.virtualDisplay.resolution}.bin"
            "video=${config.modules.virtualDisplay.port}:${config.modules.virtualDisplay.resolution}@${toString config.modules.virtualDisplay.refreshRate}e"
          ];
        };
      };
  };
}
