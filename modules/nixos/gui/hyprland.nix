{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.modules.gui.enable {
    programs = {
      hyprland = {
        enable = false;
        withUWSM = true;
      };
    };
  };
}
