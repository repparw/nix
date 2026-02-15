{
  pkgs,
  lib,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.gaming.enable {
    programs.lutris.enable = true;
    home.packages = with pkgs; [
      heroic
    ];
  };
}
