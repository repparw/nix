{
  den,
  ...
}:
{
  den.aspects.ai.provides.t3code-connect = {
    homeManager =
      {
        config,
        lib,
        osConfig,
        pkgs,
        ...
      }:
      let
        launcher = pkgs.writeShellScript "t3code-desktop" ''
          export CODEX_HOME=${lib.escapeShellArg config.home.sessionVariables.CODEX_HOME}
          exec ${lib.getExe' config.programs.t3code.package "t3code-desktop"} "$@"
        '';
      in
      {
        xdg.desktopEntries.t3code = lib.mkIf (osConfig.modules.desktop.enable or false) {
          name = "T3 Code (Alpha)";
          exec = "${launcher} %U";
          icon = "t3code";
          settings.StartupWMClass = "t3code";
          categories = [ "Development" ];
          mimeType = [ "x-scheme-handler/t3code" ];
        };
      };

    nixos =
      { config, lib, ... }:
      {
        # Desktop-only integration (.env for the Electron app, launcher
        # entry): headless hosts use the stock binary so the package keeps
        # substituting from the binary cache instead of rebuilding locally.
        nixpkgs.overlays = lib.mkIf (config.modules.desktop.enable or false) [
          (final: prev: {
            t3code = prev.t3code.override {
              t3code-unwrapped = prev.t3code.unwrapped.overrideAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  cp .env.example .env
                '';
                desktopItems = (old.desktopItems or [ ]) ++ [
                  (final.makeDesktopItem {
                    name = "t3code";
                    desktopName = "T3 Code (Alpha)";
                    exec = "t3code-desktop %U";
                    terminal = false;
                    icon = "t3code";
                    startupWMClass = "t3code";
                    categories = [ "Development" ];
                    mimeTypes = [ "x-scheme-handler/t3code" ];
                  })
                ];
              });
            };
          })
        ];
      };
  };
}
