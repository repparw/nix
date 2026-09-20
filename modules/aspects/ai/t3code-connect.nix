{
  den,
  ...
}:
{
  den.aspects.ai.provides.t3code-connect = {
    nixos = {
      nixpkgs.overlays = [
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
