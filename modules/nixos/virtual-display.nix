{
  config,
  lib,
  ...
}:

{
  options.modules.virtualDisplay = {
    enable = lib.mkEnableOption "Virtual display for Sunshine/Moonlight";
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

  config = lib.mkIf config.modules.virtualDisplay.enable {
    boot.kernelParams = [
      "video=${config.modules.virtualDisplay.port}:${config.modules.virtualDisplay.resolution}@${toString config.modules.virtualDisplay.refreshRate}e"
    ];
  };
}
