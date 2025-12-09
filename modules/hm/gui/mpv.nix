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
        ytdl-raw-options = "format=bestvideo[height<=?1080]+bestaudio/best,sub-format=en/es,write-srt=";
        screen = 1;
        fs = "yes";
        fs-screen = 1;

        hwdec = "vaapi";
        vo = "gpu-next";
        gpu-api = "vulkan";
        gpu-context = "waylandvk";

        screenshot-template = "%F - %p %02n";
        screenshot-dir = "~/Pictures/mpvss";

        osc = "no";
        osd-font-size = 32; # Default 55
        osd-border-size = 2; # Default 3

        sub-font-size = 36; # Default 55
        sub-border-size = 0.5; # Default 3
        sub-shadow-offset = 2;
        sub-blur = 0.5;

        slang = "eng";
        sub-auto = "fuzzy";
      };
    };
  };
}
