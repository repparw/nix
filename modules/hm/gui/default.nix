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
        vesktop
        pwvucontrol
        scrcpy

        obsidian

        # find pomo app in nixpkgs
      ]
      ++ (with pkgs.stable; [
        ]);

    gtk = {
      enable = true;
      theme = {
        name = "Gruvbox-Dark";
        package = pkgs.gruvbox-gtk-theme;
      };
      iconTheme = {
        name = "Gruvbox-Dark";
        package = pkgs.gruvbox-gtk-theme;
      };
      gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    };

    home.pointerCursor = {
      name = "Capitaine Cursors (Gruvbox)";
      package = pkgs.capitaine-cursors-themed;
      size = 24;
      gtk.enable = true;
      hyprcursor.enable = true;
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
      };
    };

    programs = {
      kitty = {
        enable = true;
        themeFile = "GruvboxMaterialDarkMedium";
        font = {
          name = "FiraCode Nerd Font Mono";
          size = 12;
        };
        settings = {
          disable_ligatures = "cursor";
          enable_audio_bell = "no";
          window_margin = "2 2 0";
          window_padding_width = "1 1 0";
          confirm_os_window_close = 0;
          background_opacity = "0.9";
        };
      };

      chromium.enable = true;

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
