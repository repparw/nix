export $(systemctl --user show-environment | grep '^NIRI_SOCKET=')
niri msg output DP-2 on
niri msg output DP-2 mode "2560x1440@119.986"
