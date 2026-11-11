{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.ai.provides.t3code = {
    nixos = {
      # T3 launches the chrome-headless-shell it downloads at runtime. That is
      # a generic Linux ELF, so NixOS needs the nix-ld interpreter stub before
      # it can run at all; the browser libraries ride on the pin
      # (NixOS/nixpkgs#575675, watcher t3code-browser-libs).
      programs.nix-ld.enable = true;
    };

    homeManager =
      {
        lib,
        pkgs,
        config,
        ...
      }:
      let
        hasStylix = config.lib ? stylix;
        c = config.lib.stylix.colors.withHashtag;
        mutedText = "${c.base05}cc";
        stylixThemeJson = builtins.toJSON {
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
        programs.t3code.enable = true;
        programs.t3code.package = lib.mkDefault (
          if pkgs ? t3code-desktop then pkgs.t3code-desktop else pkgs.t3code
        );

        home.activation.t3codeStylixTheme = lib.mkIf hasStylix (
          let
            themeFile = pkgs.writeText "t3code-stylix-theme.json" stylixThemeJson;
          in
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            mkdir -p "${config.home.homeDirectory}/.t3/userdata/themes"
            cp --remove-destination ${lib.escapeShellArg themeFile} "${config.home.homeDirectory}/.t3/userdata/themes/stylix.json"
          ''
        );

        programs.t3code.userSettings =
          lib.optionalAttrs hasStylix {
            defaultTheme = "stylix";
            defaultThemeSetAt = builtins.hashString "sha256" stylixThemeJson;
          }
          // {
            providerInstances.opencode = {
              driver = "opencode";
              enabled = true;
              config = {
                enabled = true;
                binaryPath = "${config.programs.opencode.package}/bin/opencode";
                serverUrl = "";
              };
            };
          };

        programs.t3code.server = {
          enable = true;
          extraArgs = [
            "--mode"
            "web"
          ];
          environmentFile = pkgs.writeText "t3code-environment" ''
            CODEX_HOME=${config.xdg.configHome}/codex
          '';
        };
      };
  };
}
