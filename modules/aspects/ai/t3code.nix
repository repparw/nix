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
            terminalSelection = c.base02;
            terminalScrollbar = c.base02;
            terminalScrollbarHover = c.base03;
          };
        };
      in
      lib.mkMerge [
        {
          # The retired stable010 bridge is the source of this floor; keep it
          # here so a pin downgrade fails evaluation instead of installing a
          # release without the stable V2 behavior.
          assertions = [
            {
              assertion = lib.versionAtLeast config.programs.t3code.package.version "0.1.5";
              message = "T3 Code stable V2 requires t3code >= 0.1.5 in the nixpkgs pin.";
            }
          ];

          programs.t3code = {
            enable = true;
            package = lib.mkDefault (if pkgs ? t3code-desktop then pkgs.t3code-desktop else pkgs.t3code);

            userSettings = {
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

            server = {
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
        }

        (lib.mkIf hasStylix {
          # The environment-theme loader opens files with O_NOFOLLOW, so a
          # Home Manager home.file symlink is ignored. Publish a regular file
          # atomically and replace any symlink left by older configurations.
          home.activation.t3codeStylixTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            theme_dir="${config.home.homeDirectory}/.t3/userdata/themes"
            theme_source="${pkgs.writeText "t3code-stylix-theme.json" stylixThemeJson}"
            ${pkgs.coreutils}/bin/mkdir -p "$theme_dir"
            if [ -L "$theme_dir/stylix.json" ] || ! ${pkgs.coreutils}/bin/cmp -s "$theme_source" "$theme_dir/stylix.json"; then
              theme_tmp=$(${pkgs.coreutils}/bin/mktemp "$theme_dir/.stylix.json.XXXXXXXX")
              ${pkgs.coreutils}/bin/cp "$theme_source" "$theme_tmp"
              ${pkgs.coreutils}/bin/chmod 0644 "$theme_tmp"
              ${pkgs.coreutils}/bin/mv -fT "$theme_tmp" "$theme_dir/stylix.json"
            fi
          '';

          programs.t3code.userSettings = {
            defaultTheme = "stylix";
            defaultThemeSetAt = builtins.hashString "sha256" stylixThemeJson;
          };
        })
      ];
  };
}
