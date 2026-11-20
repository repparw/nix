{
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.stylix = {
    url = "github:nix-community/stylix";
    inputs = {
      flake-parts.follows = "flake-parts";
      nixpkgs.follows = "nixpkgs";
      systems.follows = "systems";
    };
  };

  flake-file.inputs.wallpapers = {
    url = "github:repparw/wallpapers";
    flake = false;
  };

  den.aspects.style = {
    nixos =
      { pkgs, config, ... }:
      {
        imports = [ inputs.stylix.nixosModules.stylix ];

        stylix =
          let
            theme = "${pkgs.base16-schemes}/share/themes/tokyodark-terminal.yaml";

            # Original generated image from the repparw/wallpapers input.
            inputImage = "${inputs.wallpapers}/wallpapers/violet-monolith.png";

            brightness = -15;
            contrast = 0;
            fillColor = "black";

            wallpaper = pkgs.runCommand "dimmed-wallpaper.jpg" { } ''
              ${lib.getExe' pkgs.imagemagick "convert"} "${inputImage}" -brightness-contrast ${toString brightness},${toString contrast} -fill ${fillColor} $out
            '';
          in
          {
            enable = true;
            polarity = "dark";

            base16Scheme = theme;
            image = wallpaper;

            fonts = {
              sansSerif = {
                name = "GoogleSansCode Nerd Font";
                package = pkgs.nerd-fonts.googlesanscode;
              };
              serif = {
                name = "GoogleSansCode Nerd Font";
                package = pkgs.nerd-fonts.googlesanscode;
              };
              monospace = {
                name = "GoogleSansCode Nerd Font Mono";
                package = pkgs.nerd-fonts.googlesanscode;
              };

              sizes = {
                applications = 12;
                desktop = 12;
                terminal = 12;
                popups = 12;
              };
            };

            cursor = {
              package = pkgs.rose-pine-cursor;
              name = "BreezeX-RosePine-Linux";
              size = 24;
            };

            opacity = {
              terminal = 0.95;
              popups = 0.75;
            };
          };

        home-manager.sharedModules = [
          {
            home.pointerCursor = {
              enable = true;
              dotIcons.enable = false;
            };
            stylix = {
              icons = {
                enable = true;
                dark = "Papirus";
                package = pkgs.papirus-icon-theme;
              };
              targets = {
                x11.enable = false;
                sxiv.enable = false;
                gtk.flatpakSupport.enable = false;
                nixvim = {
                  transparentBackground = {
                    main = true;
                    numberLine = true;
                    signColumn = true;
                  };
                };
                firefox = {
                  colorTheme.enable = true;
                  profileNames = [
                    "default"
                  ];
                };
                swaylock.image.enable = false;
              };
            };
          }
        ];
      };

    # T3 Code maps its environment theme roles onto the Stylix palette. The
    # theme lives in the style aspect because it is a palette concern; the
    # t3code aspect pulls it in so the theme follows the application.
    provides.t3code-theme.homeManager =
      { config, ... }:
      let
        c = config.lib.stylix.colors.withHashtag;
        mutedText = "${c.base05}cc";
        stylixTheme = {
          version = 1;
          name = "Stylix";
          appearance = "dark";
          colors = {
            canvas = c.base00;
            chrome = c.base00;
            toolbar = c.base00;
            toolbarForeground = c.base05;
            toolbarBorder = c.base02;
            toolbarControl = c.base01;
            toolbarControlForeground = c.base05;
            toolbarControlHover = c.base02;
            surface = c.base01;
            surfaceRaised = c.base02;
            surfaceOverlay = c.base02;
            text = c.base05;
            textMuted = mutedText;
            border = c.base02;
            input = c.base02;
            focus = c.base0D;
            accent = c.base0D;
            accentForeground = c.base00;
            secondary = c.base02;
            secondaryForeground = c.base05;
            muted = c.base01;
            mutedForeground = mutedText;
            placeholder = mutedText;
            secondaryLabel = mutedText;
            iconMuted = mutedText;
            error = c.base08;
            errorForeground = c.base08;
            errorSurface = "${c.base08}1a";
            warning = c.base0A;
            warningForeground = c.base0A;
            warningSurface = "${c.base0A}1a";
            update = c.base0D;
            updateForeground = c.base0D;
            updateSurface = "${c.base0D}1a";
            accentSurface = c.base02;
            accentSurfaceForeground = c.base05;
            messageSurface = c.base02;
            messageForeground = c.base05;
            messageAction = c.base0D;
            messageActionForeground = c.base00;
            messageActionHover = c.base0E;
            codeBackground = c.base01;
            codeForeground = c.base05;
            searchMatchBackground = c.base0A;
            searchMatchForeground = c.base00;
            searchMatchActiveBackground = c.base09;
            searchMatchActiveForeground = c.base00;
            sidebar = c.base01;
            sidebarForeground = c.base05;
            sidebarMutedForeground = mutedText;
            sidebarControlSurface = c.base02;
            sidebarRowHover = c.base02;
            sidebarRowActive = c.base03;
            sidebarRowSelected = c.base02;
            sidebarBorder = c.base02;
            terminalBackground = c.base00;
            terminalForeground = c.base05;
            terminalCursor = c.base0D;
            terminalSelection = "${c.base0D}4d";
            terminalScrollbar = c.base02;
            terminalScrollbarHover = c.base03;
          };
        };
      in
      {
        programs.t3code = {
          themes.stylix = stylixTheme;
          userSettings.defaultTheme = "stylix";
        };
      };
  };
}
