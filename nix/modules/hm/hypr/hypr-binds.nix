{ inputs, config, lib, pkgs, ... }:

{

wayland.windowManager.hyprland.settings = {
  "$mod" = "SUPER";

  bindr = [
	"$mod, SUPER_L, exec, $desktopmenu"
	"$mod ALT, SUPER_L, exec, $cmdmenu"
  ];
  bindm = [
	"$mod, mouse:272, movewindow"
	"$mod, mouse:273, resizewindow"
  ];
  binde = [
	# Resize window
	"$mod ALT, H, resizeactive, -10 0"
	"$mod ALT, J, resizeactive, 0 10"
	"$mod ALT, K, resizeactive, 0 -10"
	"$mod ALT, L, resizeactive, 10 0"
  ];
  bindl = [
	"CTRL ALT, L, exec, $lockscreen; $screenoff"
  ];
  bind = [
	"ALT, Tab, focusmonitor,+1 "
	"SHIFT ALT, Tab, movewindow,mon:+1"
	"$mod, comma, movecurrentworkspacetomonitor,l"
	"$mod, period, movecurrentworkspacetomonitor,r"

	# Scroll through monitor active workspaces with mainMod + scroll
	"$mod, C, workspace, m+1"
	"$mod SHIFT, C, workspace, previous"

	", mouse:276, workspace, m+1"

	"$mod, Q, exec, $terminal"
	"$mod, RETURN, exec, $terminal"
	"$mod, W, killactive,"
	"$mod, M, exec, hdrop $spotify"
	"$mod, E, exec, $fileManager"
	"$mod, F, fullscreen"
	"$mod SHIFT, F, fullscreen, 2"
	"$mod SHIFT ALT, F, fakefullscreen"
	"$mod ALT, F, togglefloating"
	"$mod SHIFT, E, exec, $GUIfileManager"
	"$mod, SPACE, exec, $browser"
	"$mod ALT, SPACE, exec, $socials"
	"$mod SHIFT, SPACE, exec, $browser2"
	"$mod, T, exec, $top"
	"$mod, Y, exec, [monitor $display2;workspace 6 silent;fullscreen;noinitialfocus] $kiosk"
	"$mod, U, exec, ~/.config/scripts/update"
	"$mod, V, exec, ~/.config/scripts/jelly"
	"$mod, Z, exec, ~/.config/scripts/mpvclip"
	"$mod, N, exec, $notes"
	"$mod, R, exec, $terminal zsh -ic rpi"
	"$mod, B, exec, ~/.config/scripts/bttoggle"
	"$mod, P, exec, [monitor $display2;workspace 6 silent;float;size 5% 3%;move 79% 2%] hdrop $pomodoro"

	"$mod, G, exec, xdg-open https://mail.google.com"
	"$mod, X, exec, xdg-open https://app.todoist.com/app/project/personal-2302473483"

	", Print, exec, grimblast --notify copysave screen ## Both monitors"
	"Shift, Print, exec, grimblast --notify copysave output ## Active monitor"
	"$mod, Print, exec, grimblast --notify copysave active ## Active window"
	", mouse:277, exec, grimblast --freeze copysave area ## Region"

	# Macropad
	"CTRL ALT SHIFT, A, exec, hdrop steam"
	"CTRL ALT SHIFT, B, exec, ~/.config/scripts/obs_togglerec"
	"CTRL ALT SHIFT, C, exec, ~/.config/scripts/obs_last_remux2wsp"
	"CTRL ALT SHIFT, D, exec, ~/.config/scripts/obs_buffer"
	"CTRL ALT SHIFT, E, exec, hdrop $discord"
	"CTRL ALT SHIFT, F, exec, pactl set-source-mute @DEFAULT_SOURCE@ toggle"
	# CTRL ALT SHIFT, G, exec, 
	"CTRL ALT SHIFT, H, exec, hdrop $spotify"

	# Media keys
	"bind=, XF86AudioPlay, exec, playerctl play-pause"
	"bind=, XF86AudioPause, exec, playerctl play-pause"
	"bind=, XF86AudioNext, exec, playerctl next"
	"bind=, XF86AudioPrev, exec, playerctl previous"

	# Move focus with mainMod + arrow keys
	"$mod, H, movefocus, l"
	"$mod, J, movefocus, d"
	"$mod, K, movefocus, u"
	"$mod, L, movefocus, r"

	# Move window
	"$mod SHIFT, H, movewindow, l"
	"$mod SHIFT, J, movewindow, d"
	"$mod SHIFT, K, movewindow, u"
	"$mod SHIFT, L, movewindow, r"

	# Example special workspace (scratchpad)
	"$mod, S, togglespecialworkspace, magic"
	"$mod SHIFT, S, movetoworkspace, special:magic"

	# Scroll through monitor active workspaces with mainMod + scroll
	"$mod, mouse_down, workspace, m+1"
	"$mod, mouse_up, workspace, m-1"
  ];
}
