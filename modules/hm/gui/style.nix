{pkgs, ...}: {
  home.pointerCursor = {
    name = "Capitaine Cursors (Gruvbox)";
    package = pkgs.capitaine-cursors-themed;
    size = 24;
    gtk.enable = true;
    hyprcursor.enable = true;
  };

  stylix = {
    enable = true;
    autoEnable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-material-dark-medium.yaml";
    polarity = "dark";

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
    };

    opacity = {
      terminal = 0.9;
      desktop = 1.0;
      popups = 0.75;
    };
  };
}
