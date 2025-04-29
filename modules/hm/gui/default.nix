{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.modules.gui;
in {
  options.modules.gui.enable = lib.mkEnableOption "gui";

  imports = [
    ./firefox.nix
    ./gaming.nix
    ./hypr
    ./mpv.nix
    ./spotify-player.nix
    ./spotifyd.nix
    ./zathura.nix
    ./jellyfin-mpv-shim.nix
    ./obs.nix
    ./kanshi.nix
  ];

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs;
      [
        pwvucontrol
        scrcpy

        obsidian

        # find pomo app in nixpkgs
      ]
      ++ (with pkgs.stable; [
        ]);

    gtk = {
      enable = true;
      gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    };

    xdg.mimeApps = {
      enable = true;
      associations.removed = {
        "application/pdf" = ["chromium-browser.desktop"];
        "inode/directory" = ["firefox.desktop"];
      };
      defaultApplications = {
        "inode/directory" = "org.gnome.Nautilus.desktop";
        "application/pdf" = [
          "org.pwmt.zathura.desktop"
          "firefox.desktop"
        ];
        "image/png" = "feh.desktop";
        "image/jpeg" = "feh.desktop";
        "image/gif" = "feh.desktop";
        "image/webp" = "feh.desktop";
        "text/html" = "firefox.desktop";
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
        "x-scheme-handler/about" = "firefox.desktop";
        "x-scheme-handler/unknown" = "firefox.desktop";
        "x-scheme-handler/mailto" = "firefox.desktop";
      };
    };

    programs = {
      ghostty.enable = true;

      chromium.enable = true;

      vesktop = {
        enable = true;
        settings = {
          discordBranch = "stable";
          minimizeToTray = true;
          arRPC = false;
          splashColor = "rgb(221, 199, 161)";
          splashBackground = "rgb(41, 40, 40)";
        };
      };

      feh = {
        enable = true;
        buttons = {
          zoom_in = 4;
          zoom_out = 5;
        };
        keybindings = {
          prev_img = "comma";
          next_img = "period";
        };
      };
    };
  };
}
