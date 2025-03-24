{
  config,
  lib,
  ...
}: let
  cfg = config.modules.kanshi && config.modules.gui;
in {
  options.modules.kanshi = {
    enable = lib.mkEnableOption "Kanshi display management service";
  };

  config = lib.mkIf cfg.enable {
    services.kanshi = {
      enable = true;
      systemdTarget = "graphical-session.target";
      settings = [
        {
          profile.name = "docked";
          profile.outputs = [
            {
              criteria = "eDP-1";
              status = "disable";
            }
            {
              criteria = "DP-3";
              status = "enable";
              mode = "1920x1080@60";
            }
          ];
        }
        {
          profile.name = "undocked";
          profile.outputs = [
            {
              criteria = "eDP-1";
              status = "enable";
            }
          ];
        }
      ];
    };
  };
}
