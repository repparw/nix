{ pkgs, ... }:
{
  home.packages = with pkgs; [
  ];
  ## TODO migrate pi to nixos
  ## Currently installed via dietpi-software
  # tailscale
  # docker/podman
  # podman-compose
  # unbound

  # archisteamfarm
  # mosh
  # nixvim
  # nmap
  # tmux
  # wake on lan, alias

  # zsh to fish

  # portainer running:
  # pihole
  # hass
  # hyperion
  # swag
}
