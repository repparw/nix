{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.niri = {
    includes = [ ];

    nixos =
      { pkgs, ... }:
      {
        programs.niri.enable = lib.mkDefault true;

        environment.systemPackages = [ pkgs.xwayland-satellite ];
      };

    homeManager =
      { pkgs, ... }:
      {
        home.file.".config/niri/config.kdl".text = ''
          # Niri configuration
          # See https://niri.veloxberg.org/configuration/

          # Bar
          bar {
              # Hide the bar by default, show it when needed
              hidden = true

              # Position of the bar
              position = top

              # Height of the bar in pixels
              height = 32

              # Background color of the bar
              background-color = #000000cc

              # Foreground color of the bar
              foreground-color = #ffffffff

              # Timeout in milliseconds before hiding the bar
              hide-timeout = 2000

              # Whether to show the bar on all monitors or only the focused one
              show-on-all-monitors = false
          }

          # Keybindings
          # You can find the list of available actions in the niri documentation
          # or by running `niri msg --list-actions`

          # Mod key (usually the Windows or Command key)
          set $mod Mod4

          # Basic movement
          bind $mod + h, focus left
          bind $mod + j, focus down
          bind $mod + k, focus up
          bind $mod + l, focus right

          # Moving windows
          bind $mod + Shift + h, move left
          bind $mod + Shift + j, move down
          bind $mod + Shift + k, move up
          bind $mod + Shift + l, move right

          # Resizing windows
          bind $mod + Control + h, resize shrink width
          bind $mod + Control + j, resize grow height
          bind $mod + Control + k, resize shrink height
          bind $mod + Control + l, resize grow width

          # Splitting containers
          bind $mod + Return, split horizontal
          bind $mod + Shift + Return, split vertical

          # Layouts
          bind $mod + Space, layout togglesplit
          bind $mod + Shift + Space, layout togglefloat

          # Focus the parent container
          bind $mod + a, focus parent

          # Focus the child container
          bind $mod + s, focus child

          # Kill the focused window
          bind $mod + Shift + q, kill

          # Start a terminal
          bind $mod + Enter, exec foot

          # Start the application launcher (rofi)
          bind $mod + d, exec rofi -show drun

          # Reload the configuration
          bind $mod + Shift + c, exec niri msg action reload-configuration

          # Exit niri
          bind $mod + Shift + e, exec niri msg action exit

          # Scratchpad
          set $scratchpad Scratchpad
          bind $mod + ., movetoscratchpad
          bind $mod + Shift + ., togglescratchpad

          # Workspaces
          bind $mod + 1, workspace number 1
          bind $mod + 2, workspace number 2
          bind $mod + 3, workspace number 3
          bind $mod + 4, workspace number 4
          bind $mod + 5, workspace number 5
          bind $mod + 6, workspace number 6
          bind $mod + 7, workspace number 7
          bind $mod + 8, workspace number 8
          bind $mod + 9, workspace number 9
          bind $mod + 0, workspace number 10

          bind $mod + Shift + 1, movetoworkspace number 1
          bind $mod + Shift + 2, movetoworkspace number 2
          bind $mod + Shift + 3, movetoworkspace number 3
          bind $mod + Shift + 4, movetoworkspace number 4
          bind $mod + Shift + 5, movetoworkspace number 5
          bind $mod + Shift + 6, movetoworkspace number 6
          bind $mod + Shift + 7, movetoworkspace number 7
          bind $mod + Shift + 8, movetoworkspace number 8
          bind $mod + Shift + 9, movetoworkspace number 9
          bind $mod + Shift + 0, movetoworkspace number 10

          # Monitor configuration
          # Example for DP-1 and HDMI-A-1
          # monitor DP-1 {
          #     enabled = true
          #     resolution = 3840x2160@60
          #     position = 0,0
          # }
          # monitor HDMI-A-1 {
          #     enabled = true
          #     resolution = 1920x1080@60
          #     position = 3840,0
          # }
        '';
      };
  };
}
