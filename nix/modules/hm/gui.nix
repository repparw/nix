{
  pkgs,
  stable,
  osConfig,
  ...
}:

{
  imports = [
    ./spotifyd.nix
    ./spotify-player.nix
  ];

  home.packages =
    with pkgs;
    [
      # GUI
      mpv
      vesktop
      pavucontrol
      obs-studio
      obs-cmd
      scrcpy
      logiops_0_2_3

      obsidian

      # find pomo app in nixpkgs
    ]
    ++ (with stable; [
      #add here and uncomment
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
      "application/pdf" = [
        "org.pwmt.zathura.desktop"
        "firefox.desktop"
      ];
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

    firefox = {
      enable = true;

      nativeMessagingHosts = [ pkgs.tridactyl-native ];

      ####profiles = {
      ####  default = {
      ####  	isDefault = true;
      ####	userChrome = (builtins.readFile ../source/userChrome.css);
      ####	Path="ii5adzcc.default-release";
      ####	settings = {
      ####	  "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      ####	  "layers.acceleration.force-enabled" = true;
      ####	  "gfx.webrender.all" = true;
      ####	  "gfx.webrender.enabled" = true;
      ####	  "layout.css.backdrop-filter.enabled" = true;
      ####	  "svg.context-properties.content.enabled" = true;
      ####	};
      ####  };
      ####  kiosk = {

      ####  }
      ####  socials = {
      ####};
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

    zathura = {
      enable = true;
      options = {
        notification-error-bg = "#32302f"; # bg
        notification-error-fg = "#fb4934"; # bright:red
        notification-warning-bg = "#32302f"; # bg
        notification-warning-fg = "#fabd2f"; # bright:yellow
        notification-bg = "#32302f"; # bg
        notification-fg = "#b8bb26"; # bright:green

        completion-bg = "#504945"; # bg2
        completion-fg = "#ebdbb2"; # fg
        completion-group-bg = "#3c3836"; # bg1
        completion-group-fg = "#928374"; # gray
        completion-highlight-bg = "#83a598"; # bright:blue
        completion-highlight-fg = "#504945"; # bg2

        # Define the color in index mode
        index-bg = "#504945"; # bg2
        index-fg = "#ebdbb2"; # fg
        index-active-bg = "#83a598"; # bright:blue
        index-active-fg = "#504945"; # bg2

        inputbar-bg = "#32302f"; # bg
        inputbar-fg = "#ebdbb2"; # fg

        statusbar-bg = "#504945"; # bg2
        statusbar-fg = "#ebdbb2"; # fg

        highlight-color = "#fabd2f"; # bright:yellow
        highlight-active-color = "#fe8019"; # bright:orange

        default-bg = "#32302f"; # bg
        default-fg = "#ebdbb2"; # fg
        render-loading = "true";
        render-loading-bg = "#32302f"; # bg
        render-loading-fg = "#ebdbb2"; # fg

        # Recolor book content's color
        recolor-lightcolor = "#32302f"; # bg
        recolor-darkcolor = "#ebdbb2"; # fg
        recolor = "true";
        # set recolor-keephue             true      # keep original color

        guioptions = "";

        sandbox = "none";
        statusbar-h-padding = 0;
        statusbar-v-padding = 0;
        page-padding = 1;
        selection-clipboard = "clipboard";
      };
      mappings = {
        u = "scroll half-up";
        d = "scroll half-down";
        D = "toggle_page_mode";
        r = "reload";
        R = "rotate";
        K = "zoom in";
        J = "zoom out";
        i = "recolor";
      };
    };
  };

}
