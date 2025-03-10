{ pkgs, ... }:
{
  imports = [
    ../../modules/hm/gaming.nix
    ../../modules/hm/gui/obs.nix
  ];

  services.jellyfin-mpv-shim.enable = true;

  home.packages = with pkgs; [
  ];

}
