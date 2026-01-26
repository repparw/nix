{
  osConfig,
  lib,
  ...
}:
{
  config = lib.mkIf osConfig.programs.niri.enable {
    programs.waybar = {
      enable = true;
    };
  };
}
