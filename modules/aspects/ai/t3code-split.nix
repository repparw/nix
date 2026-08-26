{
  den,
  ...
}:
{
  # Stopgap for NixOS/nixpkgs#555814 ("split desktop app into
  # t3code-desktop"), until it merges and reaches our pin: strip the Electron
  # launcher from `t3code` so every host's closure is CLI/headless only.
  #
  # The GUI need is covered by the web UI (t3code-web.service, port 3773)
  # instead of an Electron app — see the Mod+G binding in niri.nix.
  #
  # Composes with provides.t3code-title-patch in either overlay order: both
  # derive their changes from `prev.t3code.unwrapped` rather than replacing
  # each other's work.
  den.aspects.ai.provides.t3code-split = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          t3code = prev.t3code.override {
            t3code-unwrapped = prev.t3code.unwrapped.overrideAttrs (old: {
              postFixup = (old.postFixup or "") + ''
                rm -rf "$out/bin/t3code-desktop" \
                  "$out/share/applications" "$out/share/icons"
              '';
              meta = (old.meta or { }) // {
                mainProgram = "t3";
              };
            });
          };
        })
      ];
    };
  };
}
