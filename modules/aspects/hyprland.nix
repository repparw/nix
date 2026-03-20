{
  den,
  lib,
  ...
}:
{
  den.aspects.hyprland = {
    includes = [ ];

    nixos =
      { config, ... }:
      {
        config = lib.mkIf config.modules.gui.enable {
          programs.hyprland = {
            enable = false;
            withUWSM = true;
          };
        };
      };

    homeManager =
      { osConfig, ... }:
      {
        config = lib.mkIf osConfig.programs.hyprland.enable {
          wayland.windowManager.hyprland = {
            enable = true;
          };
        };
      };
  };
}
