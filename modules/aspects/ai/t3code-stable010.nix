{ den, ... }:
{
  den.aspects.ai.provides.t3code-stable010.nixos =
    { lib, ... }:
    {
      # Version only; Connect and the server split have independent lifetimes.
      nixpkgs.overlays = lib.mkBefore [
        (
          final: prev:
          let
            overrideVersion =
              package:
              package.overrideAttrs (
                finalAttrs: _: {
                  version = "0.1.1";
                  src = prev.fetchFromGitHub {
                    owner = "pingdotgg";
                    repo = "t3code";
                    tag = "v${finalAttrs.version}";
                    hash = "sha256-kIGiC/uCDgRlqt+8/zZ9K48NBuCGJ1TgqW+rpdZgZUQ=";
                  };
                  pnpmDeps = prev.fetchPnpmDeps {
                    pnpm = prev.pnpm_11;
                    inherit (finalAttrs)
                      pname
                      version
                      src
                      pnpmWorkspaces
                      ;
                    fetcherVersion = 4;
                    hash = "sha256-witoens1UicKE+SIQCrRk9YtbAVIW5x+2MqDrFh4F0s=";
                  };
                }
              );
          in
          if prev ? t3code-cli then
            {
              t3code-cli = prev.t3code-cli.override {
                t3code-unwrapped = overrideVersion prev.t3code-cli.unwrapped;
              };
              t3code-desktop = prev.t3code-desktop.override { t3code-cli = final.t3code-cli; };
            }
          else
            {
              t3code = prev.t3code.override {
                t3code-unwrapped = overrideVersion prev.t3code.unwrapped;
              };
            }
        )
      ];
    };
}
