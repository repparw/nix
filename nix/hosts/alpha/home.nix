{ pkgs, ... }:
{
  imports = [ ../../modules/hm/gaming.nix ];

  home.packages = with pkgs; [
    # Essential packages
    jellyfin-mpv-shim
  ];

}
