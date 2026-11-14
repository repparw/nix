{
  den,
  ...
}:
{
  den.aspects.ai.provides.t3code.provides.to-hosts.nixos = {
      # Temporary Connect build fix. Remove this file when nixpkgs#555921 reaches the pin.
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
}
