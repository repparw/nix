{
  pkgs,
  lib,
  osConfig,
  ...
}: {
  config = lib.mkIf osConfig.modules.gaming.enable {
    home.packages = with pkgs; [
      # Gaming
      wineWowPackages.waylandFull
      lutris
      heroic
      mangohud
    ];
  };
}
