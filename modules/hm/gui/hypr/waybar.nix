{
  osConfig,
  lib,
  ...
}:
{
  config = lib.mkIf osConfig.programs.hyprland.enable {
    programs.waybar = {
      enable = true;
      systemd.enable = true;
      settings = {
        mainBar = {
          position = "top";
          ${if osConfig.networking.hostName == "alpha" then "output" else null} = [ "HDMI-A-1" ];
          modules-left = [
            "clock#time"
          ];
          modules-center = [
            "mpris"
          ];
          modules-right = [
            "network"
            "pulseaudio"
            "battery"
            "custom/notification"
            "tray"
          ];
          #modules
          "hyprland/workspaces" = {
            disable-scroll = true;
            all-outputs = true;
            format = "{icon}";
            format-icons = {
              "1" = "";
              "2" = "󰈹";
              "3" = "";
              "4" = "";
              "5" = "";
              "6" = "";
              "7" = "󰈹";
              "8" = "";
              "9" = "";
              "0" = "";
              "urgent" = "";
              "focused" = "";
              "default" = "";
            };
          };
          "mpris" = {
            dynamic-len = 70;
            artist-len = 20;
            dynamic-importance-order = [
              "title"
              "position"
              "length"
              "album"
              "artist"
            ];
            format = "{player_icon} {dynamic}";
            format-paused = "{status_icon} <i>{dynamic}</i>";
            player-icons = {
              default = "󰲸";
              firefox = "󰈹";
              mpv = "󰐌";
            };
            status-icons = {
              paused = "󰏤";
              playing = "";
              stopped = "";
            };
          };
          "hyprland/submap" = {
            format = "<span style=\"italic\">{}</span>";
          };
          "hyprland/window" = {
            format = "{}";
            max-length = 50;
            tooltip = false;
          };
          "tray" = {
            spacing = 6;
          };
          "clock#time" = {
            timezone = "America/Argentina/Buenos_Aires";
            interval = 10;
            format = "  {:%H:%M}";
            tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          };
          "network" = {
            format-wifi = "<span color=\"#ebdbb2\"></span>  {essid}";
            format-ethernet = "󰛳";
            format-linked = "{ifname} (No IP) ";
            format-disconnected = "󰅛";
            family = "ipv4";
            tooltip-format-wifi = "  {ifname} @ {essid}\nIP: {ipaddr}\nStrength: {signalStrength}%\nFreq: {frequency}MHz\n {bandwidthUpBits}  {bandwidthDownBits}";
            tooltip-format-ethernet = "󰈁 {ifname}\nIP: {ipaddr}\n {bandwidthUpBits}  {bandwidthDownBits}";
            on-click = "kitty nmtui";
          };
          "pulseaudio" = {
            scroll-step = 3; # %, can be a float
            format = "{icon} {volume:2}% {format_source}";
            format-bluetooth = "{icon} {volume}%  {format_source}";
            format-bluetooth-muted = "{icon}   {format_source}";
            format-muted = " {format_source}";
            format-source = "";
            format-source-muted = "<span color=\"#fb4833\"></span>";
            format-icons = {
              headphone = "";
              hands-free = "";
              headset = "";
              phone = "";
              portable = "";
              car = "";
              default = [
                ""
                ""
                ""
              ];
            };
            on-click = "pwvucontrol";
            on-click-right = "wpctl set-source-mute @DEFAULT_SOURCE@ toggle";
          };
          "battery" = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} {capacity}%";
            format-charging = "󰂄 {capacity}%";
            format-plugged = "󱐋{capacity}%";
            format-alt = "{time} {icon}";
            format-full = "󰂄 {capacity}%";
            format-icons = [
              "󰁻"
              "󰁽"
              "󰂁"
            ];
          };
          "custom/notification" = {
            tooltip = false;
            format = "{icon}";
            format-icons = {
              notification = "<span foreground='red'><sup></sup></span>";
              none = "";
              dnd-notification = "<span foreground='red'><sup></sup></span>";
              dnd-none = "";
              inhibited-notification = "<span foreground='red'><sup></sup></span>";
              inhibited-none = "";
              dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
              dnd-inhibited-none = "";
            };
            return-type = "json";
            exec-if = "which swaync-client";
            exec = "swaync-client -swb";
            on-click = "swaync-client -t -sw";
            on-click-right = "swaync-client -d -sw";
            escape = true;
          };
        };
      };
      style = lib.mkAfter ''
        #workspaces,
        #clock,
        #pulseaudio,
        #network,
        #battery,
        #custom-notification,
        #tray,
        #mpris {
          margin: 0 4px;
        }
      '';
    };
  };
}
