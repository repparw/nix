{ den, ... }:
{
  den.aspects.gui = {
    includes = with den.aspects.gui._; [
      session
      niri
      obs
      browser
      mpv
      spotify
      wm
      zathura
      guiApps
    ];
  };

  den.aspects.gui.provides.session = {
    nixos = _: {
      programs.nautilus-open-any-terminal = {
        enable = true;
        terminal = "foot";
      };

      services.displayManager = {
        defaultSession = "niri";
        autoLogin.user = "repparw";
        sddm = {
          enable = true;
          wayland.enable = true;
        };
      };
    };
  };
}
