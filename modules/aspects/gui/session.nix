{ den, ... }:
{
  den.aspects.gui = {
    includes = [
      den.aspects.gui._.session
      den.aspects.gui._.niri
      den.aspects.gui._.hyprland
      den.aspects.gui._.obs
      den.aspects.gui._.browser
      den.aspects.gui._.mpv
      den.aspects.gui._.spotify
      den.aspects.gui._.wm
      den.aspects.gui._.zathura
      den.aspects.gui._.guiApps
    ];
  };

  den.aspects.gui.provides.session = {
    nixos =
      { ... }:
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
