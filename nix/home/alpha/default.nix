{ pkgs, ... }:
{
  imports = [
    ../../modules/hm/gaming.nix
    ../../modules/hm/gui/obs.nix
  ];

  home.packages = with pkgs; [
    # Essential packages
    jellyfin-mpv-shim
  ];

}
