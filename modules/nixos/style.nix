{
  pkgs,
  ...
}:
{
  stylix = {
    enable = true;

    # INFO Colorscheme change
    base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyodark-terminal.yaml";

    # image = config.lib.stylix.pixel "base00";

    image = ./rocket-surgery.png;
    # let
    #   baseUrl = "https://codeberg.org/exorcist/wallpapers/raw/commit/7b9a7511705ecd7f055fb007c467a2a66f612ca3";
    #
    #   wallpaperOptions = {
    #     dalek = "sha256-Rd30EHETeTS2+h2/8ii/+Gc29dpFHQgeYajIHqO3C9c=";
    #     penguin = "sha256-rTE57xA9FD6AuUCRH3HKJhXDNwm5fu4WMBeW9ocUM+A=";
    #     dead-robot = "sha256-WYWVgp6w4mQIzJOZXncacCSl4tm3sum3vJxvZ8gn+9I=";
    #     forest-4 = "sha256-mqrwRvJmRLK3iyEiXmaw5UQPftEaqg33NhwzpZvyXws=";
    #     houses = "sha256-p5Mo1xA4jBZh6PPP0HK2YsuEBkP/gA27YDvxtuUrPHE=";
    #     solar-system-2 = "sha256-8aVsWogIUuu6rEvGtEJ1y0NojJhEkbeAU87yPFn0d1g=";
    #     terminal-redux = "sha256-1AbBA2Lufl2gxxfn6zzkQ3/yS6gXer0rOvYMP9EdHnE=";
    #   };
    #
    #   fetchSelectedWallpaper =
    #     name:
    #     pkgs.fetchurl {
    #       url = "${baseUrl}/gruvbox/${name}.jpg";
    #       hash = wallpaperOptions.${name};
    #     };
    #
    #   selectedWallpaper = fetchSelectedWallpaper "terminal-redux";
    #
    #   # Brightness and contrast settings
    #   brightness = -10;
    #   contrast = 0;
    #   fillColor = "black";
    #
    #   # Process the image with brightness/contrast adjustments
    #   wallpaper = pkgs.runCommand "dimmed-wallpaper.jpg" { } ''
    #     ${lib.getExe' pkgs.imagemagick "convert"} "${selectedWallpaper}" -brightness-contrast ${toString brightness},${toString contrast} -fill ${fillColor} $out
    #   '';
    # in
    # wallpaper;
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
      popups = 0.75;
    };
  };
  home-manager.sharedModules = [
    {
      home.pointerCursor.dotIcons.enable = false;
      xresources.path = ".config/Xresources";
      stylix = {
        icons = {
          enable = true;
          dark = "Papirus";
          package = pkgs.papirus-icon-theme;
        };
        targets = {
          nixvim = {
            transparentBackground.main = true;
            transparentBackground.numberLine = true;
            transparentBackground.signColumn = true;
          };
          firefox.profileNames = [
            "default"
            "kiosk"
          ];
          hyprlock.useWallpaper = false;
          waybar = {
            enableCenterBackColors = true;
            enableRightBackColors = true;
          };
          noctalia-shell.enable = true;
          # niri = {
          #   enable = true;
          # };
        };
      };
    }
  ];
}
