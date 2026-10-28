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
              # The current pin still uses Node 24 / pnpm 11. Stable 0.1.3
              # requires Node 26 / pnpm 12; split packages already use them.
              (if prev ? t3code-cli then package else package.override {
                nodejs = final.nodejs_26;
                pnpm_11 = final.pnpm_12;
              }).overrideAttrs (
                finalAttrs: _: {
                  version = "0.1.3";
                  src = prev.fetchFromGitHub {
                    owner = "pingdotgg";
                    repo = "t3code";
                    tag = "v${finalAttrs.version}";
                    hash = "sha256-xxmwaHPkXzR0CAtknCc6raAzcnPtmw8wxF3YO3WcbE4=";
                  };
                  pnpmDeps = prev.fetchPnpmDeps {
                    pnpm = final.pnpm_12;
                    inherit (finalAttrs)
                      pname
                      version
                      src
                      pnpmWorkspaces
                      ;
                    fetcherVersion = 4;
                    hash = prev.lib.fakeHash; # pending fetcher-v4 hash
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
