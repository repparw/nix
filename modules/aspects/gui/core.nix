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
                    cid = 0xfd;
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

  };
}
