{
  den,
  pkgs,
  lib,
  ...
}:
{
  den.aspects.gui-core = {
    includes = [
      den.aspects.niri
      den.aspects.hyprland
      den.aspects.obs
      den.aspects.browser
      den.aspects.mpv
      den.aspects.spotify
      den.aspects.wm
      den.aspects.zathura
      den.aspects.gui-apps
    ];

    nixos =
      { pkgs, ... }:
      {
        programs = {
          wshowkeys.enable = true;
          gnome-disks.enable = true;
        };

        services.displayManager = {
          defaultSession = "niri";
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

  };
}
