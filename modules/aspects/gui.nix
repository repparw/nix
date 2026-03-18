{
  den,
  ...
}:
{
  den.aspects.gui = {
    includes = [ ];

    nixos = { ... }: {
      imports = [
        ../../lib/nixos-modules/gui
      ];
    };

    homeManager = { pkgs, ... }: {
      imports = [
        ../../lib/hm-modules/gui
      ];
    };
  };
}
