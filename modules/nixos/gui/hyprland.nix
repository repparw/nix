{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.modules.gui.enable {
    programs = {
      hyprland = {
        enable = true;
        withUWSM = true;
      };
    };
  };
}
