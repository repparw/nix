{ den, ... }:
{
  den.aspects.gui = {
    includes =
      with den.aspects.gui._;
      [
        session
        niri
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

  den.aspects.gui.provides.session = {
    nixos = { config, ... }: {
      programs.nautilus-open-any-terminal = {
        enable = true;
        terminal = "foot";
      };

      services.displayManager = {
        defaultSession = "niri";
        autoLogin.user = config.users.users.repparw.name;
        sddm = {
          enable = true;
          wayland.enable = true;
        };
      };
    };
  };
}
