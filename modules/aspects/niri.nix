{
  den,
  lib,
  ...
}:
{
  den.aspects.niri = {
    includes = [ ];

    nixos =
      { pkgs, ... }:
      {
        programs.niri.enable = lib.mkDefault true;

        environment.systemPackages = [ pkgs.xwayland-satellite ];
      };

    homeManager = { ... }: { };
  };
}
