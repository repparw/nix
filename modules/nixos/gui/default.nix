{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.modules.gui = {
    enable = lib.mkEnableOption "GUI configuration";
  };

  imports = [
    ./hyprland.nix
    ./gaming.nix
    ./obs.nix
  ];

  config = lib.mkIf config.modules.gui.enable {

    environment.etc = {
      "logid.cfg" = {
        text = ''
          devices: (
          {
            name: "MX Vertical Advanced Ergonomic Mouse";
            smartshift:
            {
              on: true;
              threshold: 30;
            };
            hiresscroll:
            {
              hires: true;
              invert: false;
              target: false;
            };
            dpi: 1600;

            buttons: (
              {
                cid: 0xfd;
                action =
                {
                  type: "Keypress";
                  keys: ["KEY_LEFTSHIFT", "KEY_LEFTMETA", "KEY_PRINT"];
                };
              }
            );
          }
          );
        '';
      };
    };

    systemd.services.logid = {
      startLimitIntervalSec = 0;
      after = [ "graphical.target" ];
      wantedBy = [ "graphical.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe pkgs.logiops_0_2_3}";
      };
    };
  };
}
