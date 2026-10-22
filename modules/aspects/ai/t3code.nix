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
        home.file.".config/t3code/themes/stylix.json" = lib.mkIf hasStylix {
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
              textMuted = c.base04;
              border = c.base02;
              input = c.base02;
              focus = c.base0D;
              accent = c.base0D;
              accentForeground = c.base00;
              secondary = c.base02;
              secondaryForeground = c.base05;
              muted = c.base01;
              mutedForeground = c.base04;
              placeholder = c.base04;
              secondaryLabel = c.base04;
              iconMuted = c.base04;
              error = c.base08;
              errorForeground = c.base07;
              errorSurface = c.base01;
              warning = c.base0A;
              warningForeground = c.base07;
              warningSurface = c.base01;
              update = c.base0D;
              updateForeground = c.base07;
              updateSurface = c.base02;
              accentSurface = c.base02;
              accentSurfaceForeground = c.base05;
              messageSurface = c.base01;
              messageForeground = c.base05;
              messageAction = c.base0D;
              messageActionForeground = c.base00;
              messageActionHover = c.base0E;
              codeBackground = c.base01;
              codeForeground = c.base05;
              sidebar = c.base01;
              sidebarForeground = c.base05;
              sidebarMutedForeground = c.base04;
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

        systemd.user.services.t3code-web = {
          Unit = {
            Description = "T3 Code Web Service";
            After = [ "network.target" ];
          };
          Service = {
            # Use the upstream CLI after the split; headless hosts select the local split until then.
            ExecStart = "${
              if pkgs ? t3code-cli then pkgs.t3code-cli else config.programs.t3code.package
            }/bin/t3 serve --mode web";
            Restart = "always";
            RestartSec = 5;
            Environment = (lib.mapAttrsToList (name: value: "${name}=${value}") providerEnvironment) ++ [
              "T3CODE_DISABLE_PROVIDER_UPDATE_NOTIFICATIONS=1"
            ];
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      };
  };
}
