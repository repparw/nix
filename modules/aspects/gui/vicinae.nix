{ den, lib, ... }:
{
  den.aspects.gui.provides.vicinaeLatest = {
    nixos = _: {
      nixpkgs.overlays = [
        (final: prev: {
          vicinae =
            if lib.versionOlder prev.vicinae.version "0.21.5" then
              let
                src = final.fetchFromGitHub {
                  owner = "vicinaehq";
                  repo = "vicinae";
                  rev = "v0.21.5";
                  hash = "sha256-YfjLenoOKwRlR/ZDUjatSC3no1e0Q2TIHkVuIMpY8Bo=";
                };
              in
              final.callPackage (src + "/nix/vicinae.nix") { }
            else
              prev.vicinae;
        })
      ];
    };
  };
}
