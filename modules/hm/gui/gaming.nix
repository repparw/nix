{
  pkgs,
  lib,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.gaming.enable {
    home.packages = with pkgs; [
      # Gaming
      wineWowPackages.waylandFull
      lutris
      heroic
      mangohud
    ];

    home.file.".local/share/applications/steam.desktop".text =
      lib.replaceStrings [ "Exec=steam" ] [ "Exec=steam-gamescope" ]
        (lib.readFile "${pkgs.steam}/share/applications/steam.desktop");
  };
}
