{
  lib,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.gui.enable {
    programs.mpv = {
      enable = true;
      bindings = {
        WHEEL_UP = "add volume 2";
        WHEEL_DOWN = "add volume -2";
        WHEEL_LEFT = "add volume 2";
        WHEEL_RIGHT = "add volume -2";
        "." = "seek 5";
        "," = "seek -5";
        ">" = "no-osd seek 1 exact";
        "<" = "no-osd seek -1 exact";
        RIGHT = "frame-step";
        LEFT = "frame-back-step";
        "~" = "script-binding console/enable";
        "F" = "script-binding quality_menu/video_formats_toggle";
        # Play in reverse toggle
        # <bind> set-cache yes ; cycle play-dir
      };

      config = {
        volume = 50;
        slang = "eng";
        ytdl-raw-options = "format=bestvideo[height<=?1080]+bestaudio/best,sub-format=en/es,write-srt=";
        sub-auto = "fuzzy";
        screen = 1;
        fs = "yes";
        fs-screen = 1;

        hwdec = "vaapi";
        vo = "gpu-next";
        gpu-api = "vulkan";
        gpu-context = "waylandvk";

        osc = "no";
        osd-font-size = 32; # Default 55
        sub-font-size = 40; # Default 55

        osd-border-size = 2; # Default 3
        sub-border-size = 2; # Default 3
      };
    };
  };
}
