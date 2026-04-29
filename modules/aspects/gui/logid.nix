{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.logid = {
    includes = [ ];

    nixos =
      { pkgs, ... }:
      {
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
                      type = "Keypress";
                      keys: ["KEY_LEFTSHIFT", "KEY_LEFTMETA", "KEY_PRINT"];
                    };
                  }
                );
              }
              );
            '';
          };
        };

        systemd.user.services.logid = {
          startLimitIntervalSec = 0;
          after = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${lib.getExe pkgs.logiops_0_2_3}";
          };
        };
      };
  };
}
