export $(systemctl --user show-environment | grep '^NIRI_SOCKET=')
niri msg output DP-2 off
