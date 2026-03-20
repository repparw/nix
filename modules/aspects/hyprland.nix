{
  den,
  lib,
  ...
}:
{
  den.aspects.hyprland = {
    includes = [ ];

    nixos =
      { ... }:
      {
        programs.hyprland = {
          enable = false;
          withUWSM = true;
        };
      };

    homeManager =
      { osConfig, ... }:
      {
        config = lib.mkIf (osConfig.programs.hyprland.enable or false) {
          wayland.windowManager.hyprland = {
            enable = true;
          };
        };
      };
  };
}
