{
  den,
  ...
}:
{
  den.aspects.gaming = {
    includes = [ ];

    nixos = { ... }: {
      imports = [
        ../../lib/nixos-modules/gui/gaming.nix
      ];
    };
  };
}
