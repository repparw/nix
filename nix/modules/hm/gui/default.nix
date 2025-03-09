{
  pkgs,
  stable,
  ...
}:
{
  imports = [
    ./firefox.nix
    ./mpv.nix
    ./spotify-player.nix
    ./spotifyd.nix
    ./zathura.nix
  ];

  home.packages =
    with pkgs;
    [
      vesktop
      pwvucontrol
      scrcpy
      logiops

      obsidian

      # find pomo app in nixpkgs
    ]
    ++ (with stable; [
      # Add here and uncomment
    ]);

  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  gtk.enable = true;

  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "application/pdf" = [
        "org.pwmt.zathura.desktop"
        "firefox.desktop"
      ];
      "image/png" = "feh.desktop";
      "image/jpeg" = "feh.desktop";
      "image/gif" = "feh.desktop";
      "image/webp" = "feh.desktop";
    };
    associations.removed = {
      "application/pdf" = [ "chromium-browser.desktop" ];
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

  home.pointerCursor = {
    name = "Capitaine Cursors (Gruvbox)";
    package = pkgs.capitaine-cursors-themed;
    size = 24;
    gtk.enable = true;
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

}
