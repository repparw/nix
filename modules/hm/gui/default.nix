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
    home.packages =
      with pkgs;
      [
        pwvucontrol
        scrcpy

        rquickshare

        obsidian

        anki

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
        "application/pdf" = [ "chromium-browser.desktop" ];
        "inode/directory" = [ "firefox.desktop" ];
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
      kitty = {
        enable = true;
        settings = {
          disable_ligatures = "cursor";
          text_fg_override_threshold = "4.5 ratio";
          enable_audio_bell = "no";
          window_margin = "2 2 0";
          window_padding_width = "1 1 0";
          confirm_os_window_close = 0;
          input_delay = 0;
          repaint_delay = 8;
          sync_to_monitor = "no";
          wayland_enable_ime = "no";
        };
        keybindings = {
          "ctrl+backspace" = "send_text all \\x17";
        };
      };

      thunderbird = {
        enable = true;
        profiles.personal = {
          isDefault = true;
        };
      };

      chromium.enable = true;

      vesktop = {
        enable = true;
        settings = {
          discordBranch = "stable";
          minimizeToTray = true;
          arRPC = false;
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
          zoom_in = "K";
          zoom_out = "J";
        };
      };
    };
  };
}
