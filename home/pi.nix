{ pkgs, ... }:
{
  home.packages = with pkgs; [
  ];
  ## TODO migrate pi to nixos

  # wake on lan, alias

  # portainer running:
  # pihole -> services
  # hass -> services
  # hyperion -> services
  # swag

  # if combining swag's, merge crypt/dietpi-services proxy-confs with dlsuite/swag proxy-confs

}
