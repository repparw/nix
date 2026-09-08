{ den, ... }:
{
  den.aspects.gui = {
    includes =
      with den.aspects.gui._;
      [
        session
        niri
        phone
        browser
        mpv
        spotify
        wm
        zathura
        guiApps
      ]
      # Sound and theming only exist where a GUI does; headless hosts skip both.
      ++ (with den.aspects; [
        audio
        style
      ]);
  };

  den.aspects.gui.provides.session.nixos = {
    programs.nautilus-open-any-terminal = {
      enable = true;
      terminal = "foot";
    };

    services.displayManager = {
      defaultSession = "niri";
      sddm = {
        enable = true;
        wayland.enable = true;
      };
    };
  };
}
