{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.modules.gui.enable {
    programs.niri.enable = lib.mkDefault true;

    environment.systemPackages = [ pkgs.xwayland-satellite ];
  };
}
