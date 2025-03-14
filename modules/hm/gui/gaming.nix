{ pkgs, osConfig, ... }:

{
  config =
    if osConfig.modules.gaming.enable then
      {
        home.packages = with pkgs; [
          # Gaming
          wineWowPackages.waylandFull
          lutris
          heroic
          mangohud
        ];
      }
    else
      { };
}
