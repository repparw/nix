{ pkgs, ... }:
{
  imports = [
    ../common
    ../../modules/hm/gaming.nix
    ../../modules/hm/obs.nix
  ];

  home.packages = with pkgs; [
    # Essential packages
    # jellyfin-mpv-shim
  ];

}
