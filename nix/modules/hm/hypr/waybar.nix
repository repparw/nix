{ osConfig, ... }:
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      position = "top";
      ${if osConfig.networking.hostName == "alpha" then "output" else null} = "HDMI-A-1";
      modules-left =
        if osConfig.networking.hostName == "alpha" then
          ''["clock/time"]''
        else
          ''["clock/time" "hyprland/language"]'';
      modules-center = [
        "custom/arrow4"
        "mpris"
        "custom/arrow5"
      ];
      modules-right =
        if osConfig.networking.hostName == "alpha" then
          ''["clock/time"]''
        else
          ''["clock/time" "hyprland/language"]'';
      modules = [
        {
          type = "custom/text";
          exec = "echo 'Hello, World!'";
        }
      ];
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
