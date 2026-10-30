{
  den,
  lib,
  pkgs,
  ...
}:
let
  connectEnvironment = {
    T3CODE_CLERK_PUBLISHABLE_KEY = "pk_live_Y2xlcmsudDMuY29kZXMk";
    T3CODE_CLERK_JWT_TEMPLATE = "t3-relay";
    T3CODE_CLERK_CLI_OAUTH_CLIENT_ID = "hzxSgY2cH10sDU2r";
    T3CODE_RELAY_URL = "https://relay.t3.codes";
  };
in
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
        providerEnvironment = connectEnvironment // {
          CODEX_HOME = config.home.sessionVariables.CODEX_HOME;
        };
      in
      {
        home.sessionVariables = connectEnvironment;

        programs.t3code.enable = true;
        programs.t3code.package = lib.mkDefault (
          if pkgs ? t3code-desktop then pkgs.t3code-desktop else pkgs.t3code
        );

        # t3code keeps custom themes in Electron/browser localStorage and only
        # imports them through the UI (Settings -> Appearance -> Add a theme).
        # Derive an importable theme file from the stylix palette and install
        # it under the desktop userData dir; re-import after a stylix change.
        home.file.".config/t3code-v2/themes/stylix.json" = lib.mkIf hasStylix {
          text = builtins.toJSON {
            version = 1;
            id = "stylix";
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
        };

        programs.t3code.userSettings = {
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
        };

        # Home Manager builds ExecStart from programs.t3code.package and
        # server.extraArgs; only retain our explicit restart/environment policy.
        systemd.user.services.t3code.Service = {
          Restart = lib.mkForce "always";
          Environment = (lib.mapAttrsToList (name: value: "${name}=${value}") providerEnvironment) ++ [
            "T3CODE_DISABLE_PROVIDER_UPDATE_NOTIFICATIONS=1"
          ];
        };
      };
  };
}
