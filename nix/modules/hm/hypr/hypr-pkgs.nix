{ pkgs, ... }:

{

  imports = [ ./waybar.nix ];

  home.packages = with pkgs; [
    # Desktop
    libdrm
    swaybg
    wshowkeys
    # mako # dunst alt
    swaynotificationcenter
    wl-clipboard
    pulseaudio

    tesseract # ocr
    zbar # qr

    hdrop

    hyprshot
    hyprpicker
  ];

  services = {
    hypridle = {
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
            timeout = 900;
            on-timeout = "hyprctl dispatch dpms off";
            on-resume = "hyprctl dispatch dpms on";
          }
          {
            timeout = 910;
            on-timeout = "loginctl lock-session";
          }
        ];
      };

    };

    wlsunset = {
      enable = true;
      temperature.night = 2500;
      latitude = -34.9;
      longitude = -57.9;
    };
  };

  programs = {
    tofi = {
      enable = true;
      settings = {
        font-size = 24;

        hint-font = true;

        text-color = "#d4be98";

        prompt-background = "#00000000";
        prompt-background-padding = 0;
        prompt-background-corner-radius = 0;

        placeholder-color = "#d4be98";
        placeholder-background = "#00000000";
        placeholder-background-padding = 0;
        placeholder-background-corner-radius = 0;

        input-background = "#00000000";
        input-background-padding = 0;
        input-background-corner-radius = 0;

        default-result-background = "#00000000";
        default-result-background-padding = 0;
        default-result-background-corner-radius = 0;

        selection-color = "#a9b665";
        selection-background = "#00000000";
        selection-background-padding = 0;
        selection-background-corner-radius = 0;

        selection-match-color = "#00000000";

        text-cursor-style = "bar";
        text-cursor-corner-radius = 0;

        prompt-text = "\"run:\"";

        prompt-padding = 0;

        placeholder-text = "\"\"";

        horizontal = false;

        min-input-width = 0;

        ### Window theming;
        clip-to-padding = true;

        width = "100%";
        height = "100%";
        border-width = 0;
        outline-width = 0;
        padding-left = "35%";
        padding-top = "35%";
        result-spacing = 25;
        num-results = 5;
        background-color = "#000000AA";
        ### Window positioning
        output = "\"\"";

        anchor = "center";

        exclusive-zone = -1;

        margin-top = 0;
        margin-bottom = 0;
        margin-left = 0;
        margin-right = 0;

        ### Behaviour;
        hide-cursor = false;

        text-cursor = true;

        history = true;

        matching-algorithm = "normal";

        require-match = true;

        auto-accept-single = false;

        hide-input = false;

        hidden-character = "\"*\"";

        physical-keybindings = true;

        print-index = false;

        drun-launch = true;

        late-keyboard-init = false;

        multi-instance = false;

        ascii-input = false;
      };
    };

    hyprlock = {
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
  };
}
