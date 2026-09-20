{
  den,
  ...
}:
{
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
