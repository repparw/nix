{
  config,
  osConfig,
  pkgs,
  lib,
  ...
}:
let
  cfg = osConfig.modules.gui;
in
{
  imports = [
    ./firefox
    ./gaming.nix
    ./hypr
    ./mpv.nix
    ./spotify.nix
    ./zathura.nix
    ./jellyfin-mpv-shim.nix
    ./obs.nix
    ./kanshi.nix
  ];

  config = lib.mkIf cfg.enable {
    home.packages =
      with pkgs;
      [
        pwvucontrol
        scrcpy

        obsidian

        anki

        planify
        # find pomo app in nixpkgs
      ]
      ++ (with pkgs.stable; [
      ]);

    gtk = {
      enable = true;
      gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    };

    xdg = {
      mimeApps = {
        enable = true;
        associations.removed = {
          "application/pdf" = [ "chromium-browser.desktop" ];
          "inode/directory" = [ "firefox.desktop" ];
        };
        defaultApplications = {
          "inode/directory" = "org.gnome.Nautilus.desktop";
          "application/pdf" = [
            "org.pwmt.zathura.desktop"
            "firefox.desktop"
          ];
          "image/jpeg" = "imv-dir.desktop";
          "image/png" = "imv-dir.desktop";
          "image/gif" = "imv-dir.desktop";
          "text/html" = "firefox.desktop";
          "x-scheme-handler/http" = "firefox.desktop";
          "x-scheme-handler/https" = "firefox.desktop";
          "x-scheme-handler/about" = "firefox.desktop";
          "x-scheme-handler/unknown" = "firefox.desktop";
          "x-scheme-handler/mailto" = "firefox.desktop";
        };
      };
    };

    programs = {
      foot.enable = true;

      chromium.enable = true;

      vesktop = {
        enable = true;
        settings = {
          minimizeToTray = true;
          arRPC = false;
        };
      };

      imv = {
        enable = true;
        settings = {
          binds = {
            "<comma>" = "prev";
            "<period>" = "next";
          };
        };
      };
    };
  };
}
