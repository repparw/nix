{pkgs, ...}: {
  stylix = {
    enable = true;
    autoEnable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-material-dark-hard.yaml";
    polarity = "dark";

    image = let
      baseUrl = "https://codeberg.org/exorcist/wallpapers/raw/commit/8c61309c0afe5654d56de46a4b3e1b298e151598";

      wallpaperOptions = {
        dalek = "sha256-Rd30EHETeTS2+h2/8ii/+Gc29dpFHQgeYajIHqO3C9c=";
        penguin = "sha256-rTE57xA9FD6AuUCRH3HKJhXDNwm5fu4WMBeW9ocUM+A=";
        dead-robot = "sha256-WYWVgp6w4mQIzJOZXncacCSl4tm3sum3vJxvZ8gn+9I=";
        forest-4 = "sha256-mqrwRvJmRLK3iyEiXmaw5UQPftEaqg33NhwzpZvyXws=";
        houses = "sha256-p5Mo1xA4jBZh6PPP0HK2YsuEBkP/gA27YDvxtuUrPHE=";
        solar-system-2 = "sha256-8aVsWogIUuu6rEvGtEJ1y0NojJhEkbeAU87yPFn0d1g=";
        terminal-redux = "sha256-1AbBA2Lufl2gxxfn6zzkQ3/yS6gXer0rOvYMP9EdHnE=";
      };

      # Function to fetch the selected wallpaper
      fetchSelectedWallpaper = name:
        pkgs.fetchurl {
          url = "${baseUrl}/gruvbox/${name}.jpg";
          hash = wallpaperOptions.${name};
        };
    in
      fetchSelectedWallpaper "dead-robot";

    fonts = {
      sansSerif = {
        name = "FiraCode Nerd Font";
        package = pkgs.nerd-fonts.fira-code;
      };
      serif = {
        name = "FiraCode Nerd Font";
        package = pkgs.nerd-fonts.fira-code;
      };
      monospace = {
        name = "FiraCode Nerd Font Mono";
        package = pkgs.nerd-fonts.fira-code;
      };

      sizes = {
        applications = 12;
        desktop = 12;
        terminal = 12;
        popups = 12;
      };
    };

    cursor = {
      name = "Capitaine Cursors (Gruvbox)";
      package = pkgs.capitaine-cursors-themed;
      size = 24;
    };

    opacity = {
      terminal = 0.9;
      desktop = 1.0;
      popups = 0.75;
    };
  };
  home-manager.sharedModules = [
    {
      home.pointerCursor.dotIcons.enable = false;
      xresources.path = ".config/Xresources";
      stylix = {
        iconTheme = {
          enable = true;
          dark = "Gruvbox-Plus-Dark";
          package = pkgs.gruvbox-plus-icons.override {
            folder-color = "grey";
          };
        };
        targets = {
          firefox.profileNames = [
            "default"
            "kiosk"
            "socials"
          ];
          waybar = {
            enableCenterBackColors = true;
            enableRightBackColors = true;
          };
          kitty.variant256Colors = true;
        };
      };
    }
  ];
}
