{ pkgs, unstable, ... }:

{
  home.packages = with pkgs; [
    # Desktop
    libdrm
    swaybg
    wshowkeys
    # mako # dunst alt
    swaynotificationcenter
    tofi
    waybar
    wl-clipboard
    pulseaudio

    # ocr
    tesseract

    hdrop

    unstable.hyprshot
    unstable.hyprpicker
  ];

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
        ignore_dbus_inhibit = false;
      };

      listener = [
        {
          timeout = 300;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 310;
          on-timeout = "loginctl lock-session";
        }
      ];
    };

  };

  services.wlsunset = {
    enable = true;
    temperature.night = 2500;
    latitude = -34.9;
    longitude = -57.9;
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        disable_loading_bar = true;
        hide_cursor = true;
        no_fade_in = false;
      };

      background = [
        {
          path = "/home/repparw/Pictures/bg/tardisblack.jpg";
          blur_passes = 3;
          blur_size = 8;
        }
      ];

      input-field = [
        {
          size = "200, 50";
          position = "0, -80";
          monitor = "";
          dots_center = true;
          fade_on_empty = false;
          outer_color = "rgb(a9b665)";
          inner_color = "rgb(282828)";
          font_color = "rgb(a9b665)";
          outline_thickness = 5;
          shadow_passes = 2;
        }
      ];
    };
  };
}
