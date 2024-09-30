{ osConfig, ... }:
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        position = "top";
        ${if osConfig.networking.hostName == "alpha" then "output" else null} = [ "HDMI-A-1" ];
        modules-left = [
          "clock/time"
        ] ++ (if osConfig.networking.hostName == "beta" then [ "hyprland/language" ] else [ ]);
        modules-center = [
          "custom/arrow4"
          "mpris"
          "custom/arrow5"
        ];
        modules-right = [
          "custom/arrow6"
          "bluetooth"
          "network"
          "custom/arrow7"
          "pulseaudio"
          "battery"
          "custom/arrow8"
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
        "bluetooth" = {
          interval = 30;
          format = "{icon}";
          format-icons = {
            enabled = "";
            disabled = "";
          };
          on-click = "blueman-manager";
        };
        "hyprland/language" = {
          format = " {}";
          max-length = 5;
          min-length = 4;
        };
        "tray" = {
          spacing = 6;
        };
        "clock/time" = {
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
          on-click = "pavucontrol";
          on-click-right = "pactl set-source-mute @DEFAULT_SOURCE@ toggle";
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
        "custom/arrow1" = {
          format = "";
          tooltip = false;
        };
        "custom/arrow2" = {
          format = "";
          tooltip = false;
        };

        "custom/arrow3" = {
          format = "";
          tooltip = false;
        };

        "custom/arrow4" = {
          format = "";
          tooltip = false;
        };

        "custom/arrow5" = {
          format = "";
          tooltip = false;
        };

        "custom/arrow6" = {
          format = "";
          tooltip = false;
        };

        "custom/arrow7" = {
          format = "";
          tooltip = false;
        };

        "custom/arrow8" = {
          format = "";
          tooltip = false;
        };

        "custom/arrow9" = {
          format = "";
          tooltip = false;
        };

        "custom/arrow10" = {
          format = "";
          tooltip = false;
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
    style = ''
      	  @keyframes blink-warning {
      		70% {
      color: @light;
      		}

      		to {
      color: @light;
      	   background-color: @warning;
      		}
      	  }

      	@keyframes blink-critical {
      	  70% {
      color: @light;
      	  }

      	  to {
      color: @light;
      	   background-color: @critical;
      	  }
      	}

      	/* Gruvbox Dark */

      	/*@define-color bg #353C4A;*/
      	@define-color light #D8DEE9;
      	/*@define-color dark @nord_dark_font;*/
      	@define-color warning #ebcb8b;
      	/*@define-color critical #BF616A;*/
      	/*@define-color mode @bg;*/
      	/*@define-color workspaces @bg;*/
      	/*@define-color workspaces @nord_dark_font;*/
      	/*@define-color workspacesfocused #655b53;*/
      	/*@define-color tray @bg;*/
      	/*@define-color workspacesfocused #4C566A;
      	  @define-color tray @workspacesfocused;
      	  @define-color sound #EBCB8B;
      	  @define-color network #5D7096;
      	  @define-color memory #546484;
      	  @define-color cpu #596A8D;
      	  @define-color temp #4D5C78;
      	  @define-color layout #5e81ac;
      	  @define-color battery #88c0d0;
      	  @define-color date #434C5E;
      	  @define-color time #434C5E;
      	  @define-color backlight #434C5E;*/
      	@define-color nord_bg #282828;
      	@define-color nord_bg_blue @bg;
      	@define-color nord_light #D8DEE9;

      	@define-color nord_dark_font #272727;


      	@define-color bg #282828;
      	@define-color critical #BF616A;
      	@define-color tray @bg;
      	@define-color mode @bg;

      	@define-color bluetint #448488;
      	@define-color bluelight #83a597;
      	@define-color magenta-dark #b16185;


      	@define-color font_gruv_normal #ebdbb2;
      	@define-color font_gruv_faded #a89985;
      	@define-color font_gruv_darker #D8DEE9;
      	@define-color font_dark_alternative #655b53;

      	/* Reset all styles */
      	* {
      border: none;
      		border-radius: 0px;
      		min-height: 0;
      		/*margin: 0.15em 0.25em 0.15em 0.25em;*/
      	}

      	/* The whole bar */
      #waybar {
      background: @bg;
      color: @light;
      	   font-family: "Fira Code Nerd Font";
      	   font-size: 9pt;
      	   font-weight: bold;
      }

      /* Each module */
      #battery,
      #clock,
      #cpu,
      #custom-layout,
      #memory,
      #mode,
      #network,
      #pulseaudio,
      #temperature,
      #custom-alsa,
      #custom-pacman,
      #custom-weather,
      #custom-gpu,
      #mpris,
      #tray,
      #backlight,
      #language,
      #custom-cpugovernor,
      #custom-scratchpad-indicator,
      #custom-notification,
      #idle_inhibitor,
      #bluetooth {
        /*    padding-left: 0.3em;
      		padding-right: 0.3em;*/
      padding: 0.6em 0.8em;
      }

      /* Each module that should blink */
      #mode,
      #memory,
      #temperature,
      #battery {
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
      }

      /* Each critical module */
      #memory.critical,
      #cpu.critical,
      #temperature.critical,
      #battery.critical {
      color: @critical;
      }

      /* Each critical that should blink */
      #mode,
      #memory.critical,
      #temperature.critical,
      #battery.critical.discharging {
        animation-name: blink-critical;
        animation-duration: 2s;
      }

      /* Each warning */
      #network.disconnected,
      #memory.warning,
      #cpu.warning,
      #temperature.warning,
      #battery.warning {
      background: @warning;
      color: @nord_dark_font;
      }

      /* Each warning that should blink */
      #battery.warning.discharging {
        animation-name: blink-warning;
        animation-duration: 3s;
      }

      /* Adding arrows to boxes */
      /*#custom-arrow1 {
        font-size: 16px;
      color: @sound;
      background: transparent;
      }

      #custom-arrow2 {
      font-size: 16px;
      color: @network;
      background: @sound;
      }

      #custom-arrow3 {
      font-size: 16px;
      color: @memory;
      background: @network;
      }

      #custom-arrow4 {
      font-size: 16px;
      color: @cpu;
      background: @memory;
      }

      #custom-arrow5 {
      font-size: 16px;
      color: @temp;
      background: @cpu;
      }

      #custom-arrow6 {
      font-size: 16px;
      color: @layout;
      background: @temp;
      }

      #custom-arrow7 {
      font-size: 16px;
      color: @battery;
      background: @layout;
      }

      #custom-arrow8 {
      font-size: 16px;
      color: @date;
      background: @battery;
      }

      #custom-arrow9 {
      font-size: 16px;
      color: @time;
      background: @date;
      }*/

      #custom-arrow1 {
        font-size: 2em;
      color: @bg;
      background: @bluetint;
      }
      #custom-arrow2 {
        font-size: 2em;
      color: @bluetint;
      background: @bg;
      }
      #custom-arrow3 {
        font-size: 2em;
      color: @font_dark_alternative;
      background: @bg;
      }
      #custom-arrow4 {
        font-size: 2.1em;
      color: @font_gruv_normal;
      background: @bg;
      }
      #custom-arrow5 {
        font-size: 2.12em;
      color: @font_gruv_normal;
      background: @bg;
      }
      #custom-arrow6 {
        font-size: 2em;
      color: @font_dark_alternative;
      background: @bg;
      }
      #custom-arrow7 {
        font-size: 2em;
      color: @bluetint;
      background: @font_dark_alternative;
      }
      #custom-arrow8 {
        font-size: 2em;
      color: @bg;
      background: @bluetint;
      }

      /* And now modules themselves in their respective order */
      #clock.time {
      background: @bg;
      color: @font_gruv_normal;
      }
      #clock.date {
      background: @bg;
      color: @font_gruv_faded;
      }

      #language {
      background: @bg;
      color: @font_gruv_normal;
      }
      /* Workspaces stuff */
      #workspaces {
      }
      #workspaces button {
      padding: 0em 1.2em;
      		 background-color: @bluetint;
      color: @font_gruv_normal;
      	   min-width: 0em;
      }
      #workspaces button.focused {
        font-weight: bolder; /* Somewhy the bar-wide setting is ignored*/
      }
      #workspaces button.urgent {
      color: #c9545d;
      opacity: 1;
      }
      #mpris {
      background: @font_gruv_normal;
      padding: 0em 1.2em;
      color: @font_dark_alternative;
      	   min-width: 0em;
      }

      #pulseaudio {
        background-color: @bluetint;
      color: @font_gruv_normal;
      	   padding-left: 0em;
      }
      #pulseaudio.muted {
      color: #fb4833;
      }
      #pulseaudio.source-muted {
        /* moved to config */
      }
      #bluetooth {
        background-color: @font_dark_alternative;
      color: @font_gruv_normal;
      }
      #network {
        background-color: @font_dark_alternative;
      color: @font_gruv_normal;
      }
      #custom-notification {
        font-family: "Fira Code Nerd Font";
      background: @bg;
      color: @font_gruv_normal;
      }
      #tray {
      background: @bg;
      color: @font_gruv_normal;
      }

      #custom-alsa {
      background: @sound;
      }
      #custom-layout {
      background: @layout;
      }
      #mode { /* Shown current Sway mode (resize etc.) */
      color: @light;
      background: @mode;
      }
      #battery {
      background: @battery;
      			background-color: @bluetint;
      color: @font_gruv_normal;
      }

      #backlight {
      background: @backlight;
      }
      #window {
        margin-right: 40px;
        margin-left: 40px;
        font-weight: normal;
      }
    '';
  };
}
