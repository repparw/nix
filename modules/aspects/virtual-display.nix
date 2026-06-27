{
  lib,
  ...
}:
{
  den.aspects.virtual-display = {
    nixos =
      { config, pkgs, ... }:
      let
        lg-oled-cx-edid = pkgs.fetchurl {
          name = "lg-oled-cx-hdmi.bin";
          url = "https://git.linuxtv.org/v4l-utils.git/plain/utils/edid-decode/data/lg-oled-cx-hdmi";
          sha256 = "0ymv630xgd5xnwpkkyz4mx3hwxnbw06rad9v1s4xvrzrqnin3b4i";
        };
      in
      {
        options.modules.virtualDisplay = {
          port = lib.mkOption {
            type = lib.types.str;
            default = "DP-2";
            description = "GPU port to use for virtual display";
          };
          resolution = lib.mkOption {
            type = lib.types.str;
            default = "3840x2160";
            description = "Resolution for virtual display";
          };
          refreshRate = lib.mkOption {
            type = lib.types.int;
            default = 120;
            description = "Refresh rate for virtual display";
          };
        };

        config = {
          hardware.firmware = [
            (pkgs.runCommand "lg-oled-cx-edid" { } ''
              mkdir -p $out/lib/firmware/edid
              cp ${lg-oled-cx-edid} $out/lib/firmware/edid/${config.modules.virtualDisplay.resolution}.bin
            '')
          ];
          boot.kernelParams = [
            "drm.edid_firmware=${config.modules.virtualDisplay.port}:edid/${config.modules.virtualDisplay.resolution}.bin"
            "video=${config.modules.virtualDisplay.port}:${config.modules.virtualDisplay.resolution}@${toString config.modules.virtualDisplay.refreshRate}e"
          ];
        };
      };
  };
}
