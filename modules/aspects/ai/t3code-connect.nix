{
  den,
  ...
}:
{
  den.aspects.ai.provides.t3code-connect = {
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
