{ den, ... }:
{
  den.aspects.streaming.provides.to-hosts = {
    nixos =
      { lib, pkgs, ... }:
      {
        # Backport nixpkgs 3e6a78982c92 until the fleet pin includes Moonshine 0.18.
        services.moonshine.package =
          if lib.versionOlder pkgs.moonshine.version "0.18.0" then
            pkgs.moonshine.overrideAttrs (
              final: previous: {
                version = "0.18.0";
                src = pkgs.fetchFromGitHub {
                  owner = "hgaiser";
                  repo = "moonshine";
                  tag = "v${final.version}";
                  hash = "sha256-bg32tFTJCNkihOvTEOsVyUt91OgEAAmL+IpRptTasNk=";
                };
                cargoHash = "sha256-hLjJMtEtmCEtZxDSu9TpETtoYMZiQ6yutAaK5k1RpLQ=";
                nativeCheckInputs = (previous.nativeCheckInputs or [ ]) ++ [
                  pkgs.writableTmpDirAsHomeHook
                ];
              }
            )
          else
            pkgs.moonshine;
      };
  };
}
