{
  den,
  lib,
  ...
}:
{
  den.aspects.niri = {
    includes = [ ];

    nixos =
      { config, pkgs, ... }:
      {
        config = lib.mkIf config.modules.gui.enable {
          programs.niri.enable = lib.mkDefault true;

          environment.systemPackages = [ pkgs.xwayland-satellite ];
        };
      };

    homeManager = { ... }: { };
  };
}
