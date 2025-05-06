{
  pkgs,
  osConfig,
  lib,
  ...
}: {
  config = lib.mkIf osConfig.programs.hyprland.enable {
    home.packages = with pkgs; [
      # Desktop
      libdrm
      wshowkeys
      wl-clipboard

      tesseract # ocr
      zbar # qr

      bemoji

      hdrop

      hyprshot
      hyprpicker

      nautilus

      where-is-my-sddm-theme
    ];

    services = {
      swaync.enable = true;

      hyprpolkitagent.enable = true;

      hyprpaper = {
        enable = true;
        settings = {
          ipc = "off";
          preload = [
            "/home/repparw/Pictures/gruvbox.jpg"
            "/home/repparw/src/kbd/docs/layout_wp.png"
          ];
          wallpaper = [
            "HDMI-A-1,contain:/home/repparw/src/kbd/docs/layout_wp.png"
            ",/home/repparw/Pictures/gruvbox.jpg"
          ];
        };
      };

      hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "hyprlock";
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
          hint-font = true;

          prompt-background-padding = 0;
          prompt-background-corner-radius = 0;

          placeholder-background-padding = 0;
          placeholder-background-corner-radius = 0;

          input-background-padding = 0;
          input-background-corner-radius = 0;

          default-result-background-padding = 0;
          default-result-background-corner-radius = 0;

          selection-background-padding = 0;
          selection-background-corner-radius = 0;

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

          require-match = true;

          auto-accept-single = false;

          hide-input = false;

          hidden-character = "\"*\"";

          drun-launch = true;

          late-keyboard-init = false;

          multi-instance = false;

          ascii-input = false;
        };
      };

      hyprlock = {
        enable = true;
      };
    };
  };
}
