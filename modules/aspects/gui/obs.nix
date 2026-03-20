{
  den,
  pkgs,
  lib,
  ...
}:
{
  den.aspects.obs = {
    includes = [ ];

    nixos =
      { config, pkgs, ... }:
      {
        config = lib.mkIf config.modules.gui.enable {
          programs.obs-studio = {
            enableVirtualCamera = true;
            plugins = with pkgs.obs-studio-plugins; [
              obs-backgroundremoval
            ];
          };
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
            ExecStart = "obs --disable-shutdown-check --startreplaybuffer --minimize-to-tray";
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
