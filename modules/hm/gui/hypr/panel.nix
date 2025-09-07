{
  osConfig,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf osConfig.programs.hyprland.enable {
    programs.hyprpanel = {
      enable = true;
      settings = {
        theme = {
          base = pkgs.fetchurl {
            url = "https://github.com/Jas-SinghFSU/HyprPanel/blob/master/themes/tokyo_night.json";
            sha256 = "sha256-1XxBQQfyW1+d8MPEtLSfxYhRdnRc72LoD+wxd9MHYzQ=";
          };
          font.size = "16px";
        };
        notifications.showActionsOnHover = true;
        menus = {
          clock = {
            time = {
              military = true;
            };
            weather.enabled = false;
          };
          dashboard.shortcuts = {
            left = {
              shortcut1 = {
                command = "firefox";
                icon = "";
                tooltip = "Firefox";
              };
              shortcut2 = {
                command = "ncmpcpp";
                icon = "";
                tooltip = "Music";
              };
              shortcut3 = {
                command = "vesktop";
                icon = "";
                tooltip = "Discord";
              };
              shortcut4 = {
                command = "rofi -show combi";
                icon = "";
                tooltip = "Search Apps";
              };
            };
            right = {
              shortcut1 = {
                command = "sleep 0.5 && hyprpicker -a";
                icon = "";
                tooltip = "Color Picker";
              };
              shortcut3 = {
                command = "hyprshot --clipboard-only -m region -zs";
                icon = "󰄀";
                tooltip = "Screenshot";
              };
            };
          };
        };
        bar = {
          clock.format = "%a %d %b %H:%M";
          network.label = false;
          bluetooth.label = false;
          launcher.icon = "";
          media.format = "{title: - }{artist}";
          layouts = {
            "0" = lib.mkIf (osConfig.networking.hostName == "alpha") { };
            "*" = {
              left = [
                "clock"
              ];
              middle = [ "media" ];
              right = [
                "network"
                "bluetooth"
                "volume"
              ]
              ++ lib.optional (osConfig.networking.hostName != "alpha") "battery"
              ++ [
                "notifications"
                "systray"
                "dashboard"
              ];
            };
          };
        };
      };
    };
  };
}
