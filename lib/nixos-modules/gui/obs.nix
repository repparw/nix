{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.modules.gui.enable {
    programs.obs-studio = {
      enableVirtualCamera = true;
      plugins = with pkgs.obs-studio-plugins; [
        obs-backgroundremoval
      ];
    };
  };
}
