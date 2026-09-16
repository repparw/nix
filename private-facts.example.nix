# Private host facts — TEMPLATE.
#
# Some host facts must be available at Nix evaluation time but must not live
# in committed plaintext (home WAN IP, precise weather location, hardware
# identifiers, service account IDs). They are supplied through the
# `host-facts` flake input declared in `modules/aspects/host-facts.nix`.
#
# Setup: create the directory /home/repparw/.config/nix/private-facts/
# (outside this repository), copy this file there as `facts.nix`, and fill
# in real values. The file is read at evaluation time. After every edit,
# refresh the input pin before rebuilding, otherwise the previous values
# are used silently:
#
#   nix flake lock --update-input host-facts
#
# (Only the narHash in flake.lock changes; no secret content leaks into it.)
#
# CI has no such directory, so every option in
# `modules/aspects/host-facts.nix` falls back to a harmless default (no
# public IP, coarse weather location) and evaluation still succeeds.
{
  # Home WAN/static IPv4. Drives the epsilon firewall allowlists (HTTPS
  # health check + Mosh) and the WireGuard home-tunnel endpoint.
  wanIp = null;

  # Glance weather widget location. Null yields the coarse default
  # "Buenos Aires, Argentina"; set a precise town only if you want it shown.
  weatherLocation = null;

  # Bluetooth device MAC targeted by `bttoggle` (exported as TOGGLE_BT_DEVICE).
  bluetoothDevice = null;
}
