{
  den,
  ...
}:
{
  # Local half of https://github.com/NixOS/nixpkgs/pull/555921, until it
  # merges and reaches our pin:
  #
  # - Bake the T3 Connect public identifiers (upstream's own `cp
  #   .env.example .env` build setup; public identifiers, not secrets).
  #   Without them the packaged client compiles its cloud config empty and
  #   renders no T3 Connect UI.
  # - Ship the t3code:// scheme in the desktop entry. The app registers it
  #   itself at runtime, but only when `app.isPackaged` is true, which never
  #   holds under the Nix Electron wrapper — so Clerk OAuth redirects die
  #   outside the app with "OAuth flow was cancelled".
  #
  # Composes with provides.t3code-title-patch and provides.t3code-split in
  # any overlay order: each derives from `prev.t3code.unwrapped` instead of
  # replacing the others' work. The split's share/applications removal on
  # headless hosts also removes the entry there, where it is unused.
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
