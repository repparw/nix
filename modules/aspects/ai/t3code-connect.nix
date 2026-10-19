{
  den,
  ...
}:
{
  den.aspects.ai.provides.t3code-connect = {
    nixos = {
      # Remove only this overlay when nixpkgs#555921 reaches the pin.
      nixpkgs.overlays = [
        (
          final: prev:
          let
            withConnect =
              package:
              package.overrideAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  cp .env.example .env
                '';
              });
          in
          if prev ? t3code-cli then
            {
              t3code-cli = prev.t3code-cli.override {
                t3code-unwrapped = withConnect prev.t3code-cli.unwrapped;
              };
              t3code-desktop = prev.t3code-desktop.override { t3code-cli = final.t3code-cli; };
            }
          else
            {
              t3code = prev.t3code.override {
                t3code-unwrapped = withConnect prev.t3code.unwrapped;
              };
            }
        )
      ];
    };

    homeManager =
      {
        config,
        lib,
        osConfig,
        pkgs,
        ...
      }:
      let
        launcher = pkgs.writeShellScriptBin "t3code-desktop-connect" ''
          export CODEX_HOME=${lib.escapeShellArg config.home.sessionVariables.CODEX_HOME}
          exec ${lib.getExe' config.programs.t3code.package "t3code-desktop"} "$@"
        '';
      in
      {
        home.packages = [ launcher ];

        # Browsers resolve URL schemes through GIO, which only consults
        # `mimeinfo.cache` associations when `mimeapps.list` names a default.
        # The app's own `xdg-mime default` call is skipped while Electron runs
        # unpackaged, so declare the handler instead of relying on runtime
        # registration. Keep it beside the desktop entry so the cleanup patch
        # leaves the permanent launcher intact.
        xdg.mimeApps = lib.mkIf (osConfig.modules.desktop.enable or false) {
          enable = true;
          defaultApplications."x-scheme-handler/t3code" = "t3code.desktop";
        };

        xdg.desktopEntries.t3code = lib.mkIf (osConfig.modules.desktop.enable or false) {
          name = "T3 Code (Alpha)";
          exec = "t3code-desktop-connect %U";
          icon = "t3code";
          settings.StartupWMClass = "t3code";
          categories = [ "Development" ];
          mimeType = [ "x-scheme-handler/t3code" ];
        };

        # Keep a user-local entry authoritative over stale desktop files left
        # by older installs. XDG menu lookup prefers this directory to the
        # Home Manager profile's share/applications directory.
        home.file.".local/share/applications/t3code.desktop" =
          lib.mkIf (osConfig.modules.desktop.enable or false)
            {
              source = "${config.home.path}/share/applications/t3code.desktop";
            };
      };
  };
}
