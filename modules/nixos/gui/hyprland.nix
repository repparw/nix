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
      wshowkeys.enable = true;
      partition-manager.enable = true;
    };

    services.displayManager = {
      defaultSession = "hyprland-uwsm";
      autoLogin = {
        enable = true;
        user = "repparw";
      };
      sddm = {
        enable = true;
        wayland.enable = true;
      };
    };

  };
}
