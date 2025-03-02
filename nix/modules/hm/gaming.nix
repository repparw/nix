{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Gaming
    wineWowPackages.waylandFull
    lutris
    heroic
    mangohud
    nexusmods-app-unfree
  ];
}
