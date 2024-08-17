{
  inputs,
  pkgs,
  unstable,
  ...
}:

{
  home.packages = with pkgs; [
    # Desktop
    libdrm
    swaybg
    wlsunset
    wshowkeys
    mako # dunst alt
    swaynotificationcenter
    tofi
    waybar
    hyprpicker
    wl-clipboard

    # hyprwm/contrib
    inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
    inputs.hyprland-contrib.packages.${pkgs.system}.hdrop
  ];

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
        ignore_dbus_inhibit = false;
        lock_cmd = "pidof hyprlock || hyprlock";
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

  programs.hyprlock = {
    enable = true;
    package = unstable.hyprlock;
    settings = {
      general = {
        disable_loading_bar = true;
        grace = 300;
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
          font_color = "rgb(202, 211, 245)";
          inner_color = "rgb(91, 96, 120)";
          outer_color = "rgb(24, 25, 38)";
          outline_thickness = 5;
          shadow_passes = 2;
        }
      ];
    };
  };
}
