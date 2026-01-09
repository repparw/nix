{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.modules.gui.enable {
    programs.niri.enable = false;
  };
}
