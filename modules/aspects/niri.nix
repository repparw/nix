{
  den,
  ...
}:
{
  den.aspects.niri = {
    includes = [ ];

    nixos = { ... }: {
      imports = [
        ../../lib/nixos-modules/gui/niri.nix
      ];
    };

    homeManager = { pkgs, ... }: {
      imports = [
        ../../lib/hm-modules/gui/wm/niri.nix
      ];
    };
  };
}
