{ den, lib, ... }:
{
  # Nixpkgs#587638 relaxes paperless-ngx's torch requirement after torch 2.15
  # made the upstream package fail its runtime dependency check. The pinned
  # nixos-unstable revision predates that fix, so keep the container buildable
  # until the channel contains the upstream merge commit.
  den.aspects.nixos-services.provides.paperless.nixos.containers.paperless.config.nixpkgs.overlays = [
    (_final: prev: {
      paperless-ngx =
        let
          package = prev.paperless-ngx.overridePythonAttrs (old: {
            pythonRelaxDeps = lib.unique ((old.pythonRelaxDeps or [ ]) ++ [ "torch" ]);
          });
        in
        package
        // {
          # overridePythonAttrs does not retain the derivation-level override
          # helper that mkPackageOption applies to Paperless' tesseract.
          override = args: package.overrideAttrs args;
        };
    })
  ];
}
