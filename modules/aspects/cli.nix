{
  den,
  ...
}:
{
  den.aspects.cli = {
    includes = [ ];

    nixos = { ... }: {
      imports = [
        ../../lib/nixos-modules/cli
      ];
    };

    homeManager = { pkgs, ... }: {
      imports = [
        ../../lib/hm-modules/cli
      ];
    };
  };
}
