{
  den,
  pkgs,
  lib,
  ...
}:
{
  den.aspects.gui.provides.obs = {
    nixos =
      { pkgs, ... }:
      {
        programs.obs-studio = {
          enableVirtualCamera = true;
          plugins = with pkgs.obs-studio-plugins; [
            obs-backgroundremoval
          ];
        };
      };

    homeManager =
      { pkgs, ... }:
      {
        systemd.user.services.obs = {
          Unit = {
            Description = "OBS Studio";
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe pkgs.obs-studio} --disable-shutdown-check --startreplaybuffer --minimize-to-tray";
            Restart = "on-failure";
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };

        home.packages = [ pkgs.obs-cmd ];
      };
  };
}
