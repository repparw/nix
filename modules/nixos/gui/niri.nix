{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.modules.gui.enable {
    programs.niri.enable = lib.mkDefault true;
  };
}
